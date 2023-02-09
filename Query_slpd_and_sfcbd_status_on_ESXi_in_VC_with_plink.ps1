# Following Environment Specific Values Needs to be set before executing the script

########### Environment Specific Values - START ###########

#vCenter FQDN or IP Address
$vcenter = "FQDN Or IP address"

#SSO Administrator Username
$UserName = "Administrator@vsphere.local"

#ESXi Credentials
$PuttyUser = “root”
$PuttyPwd = “ESXi Root Password”

#Plink Path - It will be available in Putty Installation directory eg. c:\PuTTY\plink.exe, DO NOT use path with spaces, eg. Program Files
$PlinkPath = "C:\Temp\plink.exe"

#Export Result File Name
$ResultFilename = "C:\Temp\ESXi_Query_SLPDandSFDBC_ServiceStatus.csv"

########### Environment Specific Values - END ###########

$scriptpath = $MyInvocation.MyCommand.Path | Split-Path

$scriptpath | Push-Location

$VMSAServiceStatus=@()

Add-PSSnapIn VMware* -ErrorAction SilentlyContinue
$ErrorActionPreference = "SilentlyContinue"

if (!(Test-Path $PlinkPath))
    {
        Write-Host "Plink Path $PlinkPath DOES NOT exist, please provide correct path" 
        Write-Host "Script is exiting"
        exit
    }

If ($PlinkPath  -match " ")
    {
    Copy-Item $PlinkPath $scriptpath
    $PlinkPath = "plink.exe"
    }

$Plink = “echo N | $PlinkPath”
$PlinkOptions = ” -batch -pw $PuttyPwd”

$cmd1 = ‘/etc/init.d/slpd status ‘
$RCommand1 = ‘”‘ + $cmd1 + ‘”‘

$cmd2 = ‘chkconfig slpd ‘
$RCommand2 = ‘”‘ + $cmd2 + ‘”‘


$VCCred = Get-Credential -UserName $UserName -Message "Please enter Password of SSO Credentials"
$VCConnection = Connect-VIServer -Server $vcenter -Credential $VCCred | Out-Null

$ESXiHosts = Get-VMHost

foreach ($ESXiHost in $ESXiHosts)
    {
        Write-Host "Processing Host $ESXiHost"
        $ServiceStatus = new-object PSObject
        $ServiceStatus | add-member -type NoteProperty -Name HostName -Value $ESXiHost

    if (Test-Connection $ESXiHost.Name -Count 1)
        {
        $foundslpd = $false
        $slpdServiceState, $slpdStartupPolicy, $sfcbdServiceState, $sfcbdStartupPolicy = $null
        $vmsacompliant = "No"
        $sshwasstopped=$false
   
        $ESXiServices = Get-VMHostService -VMHost $ESXiHost

        foreach ($ESXiService in $ESXiServices)
            {
                if  ($ESXiService.Key -eq "slpd")
                    {
                        $foundslpd = $true
                        if($ESXiService.Running)
                            {$ServiceState = "Running"}
                        else
                            {$ServiceState = "Stopped"}
                    
                        $slpdServiceState = $ServiceState
                        $slpdStartupPolicy = $ESXiService.Policy
                    }
                elseif ($ESXiService.Key -eq "sfcbd-watchdog")
                    {
                        if($ESXiService.Running)
                            {$ServiceState = "Running"}
                        else
                            {$ServiceState = "Stopped"}
                        $sfcbdServiceState = $ServiceState
                        $sfcbdStartupPolicy = $ESXiService.Policy
                    }
            }
    
        if(!$foundslpd)
        {
    
        $ssh = Get-VMHostService -VMHost $ESXiHost  | where{$_.Key -eq 'TSM-SSH'}
        if(!$ssh.Running)
            {
                $sshwasstopped=$true
                Start-VMHostService -HostService $ssh -Confirm:$false > $null
            }
    
        $ESXiName = $ESXiHost.Name
        $command1 = $Plink + ” ” + $PlinkOptions + ” ” + $PuttyUser + “@” + $ESXiName + ” ” + $RCommand1
        $slpdstatusresult = Invoke-Expression -command $command1
    
        if ($slpdstatusresult -like "*is running")
            {
                $slpdServiceState = "Running"
            }
        elseif($slpdstatusresult -like "*is not running")
            {
                $slpdServiceState = "Stopped"
            }
        else
            {
                $slpdServiceState = "UNKNOWN"
                echo "exiting"
                exit
            }
    
        $command2 = $Plink + ” ” + $PlinkOptions + ” ” + $PuttyUser + “@” + $ESXiName + ” ” + $RCommand2
        $slpdpolicyresult = Invoke-Expression -command $command2

        if ($slpdpolicyresult -like "*slpd*on*")
            {
                $slpdStartupPolicy = "on"
            }
        elseif($slpdpolicyresult -like "*slpd*off*")
            {
                $slpdStartupPolicy = "off"
            }
        else
            {
                $slpdStartupPolicy = "UNKNOWN"
                exit
            }


        if($sshwasstopped)
            {
            Stop-VMHostService -HostService $ssh -Confirm:$false > $null
            }
        }

        $ServiceStatus | add-member -type NoteProperty -Name slpd_CurrentStatus -Value $slpdServiceState
        $ServiceStatus | add-member -type NoteProperty -Name slpd_StartupPolicy -Value $slpdStartupPolicy
    
        $ServiceStatus | add-member -type NoteProperty -Name sfcbd_CurrentStatus -Value $sfcbdServiceState
        $ServiceStatus | add-member -type NoteProperty -Name sfcbd_StartupPolicy -Value $sfcbdStartupPolicy

        if ( ($ServiceStatus.slpd_StartupPolicy -eq "off") -and ($ServiceStatus.slpd_CurrentStatus -eq "stopped") -and ($ServiceStatus.sfcbd_StartupPolicy -eq "off") -and ($ServiceStatus.sfcbd_CurrentStatus -eq "stopped") )
        {
            $vmsacompliant = "Yes"
        }

        $ServiceStatus | add-member -type NoteProperty -Name VMSA-2021-0014_Compliant -Value $vmsacompliant
    
        }
    else
        {
        $ServiceStatus | add-member -type NoteProperty -Name slpd_CurrentStatus -Value "HOST_UNREACHABLE"
        $ServiceStatus | add-member -type NoteProperty -Name slpd_StartupPolicy -Value "HOST_UNREACHABLE"
        $ServiceStatus | add-member -type NoteProperty -Name sfcbd_CurrentStatus -Value "HOST_UNREACHABLE"
        $ServiceStatus | add-member -type NoteProperty -Name sfcbd_StartupPolicy -Value "HOST_UNREACHABLE"
        $ServiceStatus | add-member -type NoteProperty -Name VMSA-2021-0014_Compliant -Value "HOST_UNREACHABLE"
        }
        $VMSAServiceStatus+=$ServiceStatus
    }


try
{
    $VMSAServiceStatus | export-csv $ResultFilename -notype -ErrorAction Stop
    Write-Host "Please check the final result file - " $ResultFilename
}

catch
{
    $ResultFilename = "ESXiServiceStatus" + (Get-Date).tostring("dd-MM-yyyy-hh-mm-ss") + ".csv"
    $VMSAServiceStatus | export-csv $ResultFilename -notype
    $result = Get-Item $ResultFilename
    Write-Host "Please check the final result file saved in current directory - " $result.fullname
}