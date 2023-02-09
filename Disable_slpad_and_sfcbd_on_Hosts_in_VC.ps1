#vCenter FQDN or IP Address
$vcenter = "FQDN Or IP address"

#SSO Administrator Username
$UserName = "Administrator@vsphere.local"

#Array for Result export
$VMSAServiceStatus=@()

Add-PSSnapIn VMware* -ErrorAction SilentlyContinue
$ErrorActionPreference = "Stop"

#Read VC Credentials
$VCCred = Get-Credential -UserName "Administrator@vsphere.local" -Message "Please enter Password of SSO Administrator Account"

#Connect to vCenter Server
$VCConnection = Connect-VIServer -Server $vcenter -Credential $VCCred | Out-Null

# List ESXiHosts in Cluster with Connected Status
$ESXiHosts = Get-VMHost -State Connected

#Capture if slpd service is available
$slpdfound = "No"

    foreach ($ESXiHost in $ESXiHosts)
    {

        $ESXiServices = Get-VMHostService -VMHost $ESXiHost

        foreach ($ESXiService in $ESXiServices)
            {
                if  ($ESXiService.Key -eq "slpd")
                    {
                        $ESXiService | Set-VMHostService -Policy Off -Confirm:$false
                        $ESXiService | Stop-VMHostService -Confirm:$false
                    }
                elseif ($ESXiService.Key -eq "sfcbd-watchdog")
                    {
                       $ESXiService | Set-VMHostService -Policy Off -Confirm:$false
                       $ESXiService | Stop-VMHostService -Confirm:$false
                    }
            }
    
    }

    foreach ($ESXiHost in $ESXiHosts)
    {

    $vmsacompliant = "No"
    $ServiceStatus = new-object PSObject
    $ServiceStatus | add-member -type NoteProperty -Name HostName -Value $ESXiHost.Name

    $ESXiServices = Get-VMHostService -VMHost $ESXiHost

    foreach ($ESXiService in $ESXiServices)
        {
            if  ($ESXiService.Key -eq "slpd")
                {
                    $slpdfound = "Yes"
					if($ESXiService.Running)
                        {$ServiceState = "Running"}
                    else
                        {$ServiceState = "Stopped"}

                    $ServiceStatus | add-member -type NoteProperty -Name slpd_StartupPolicy -Value $ESXiService.Policy
                    $ServiceStatus | add-member -type NoteProperty -Name slpd_CurrentStatus -Value $ServiceState
                }
            elseif ($ESXiService.Key -eq "sfcbd-watchdog")
                {
                    if($ESXiService.Running)
                        {$ServiceState = "Running"}
                    else
                        {$ServiceState = "Stopped"}
                    $ServiceStatus | add-member -type NoteProperty -Name sfcbd_StartupPolicy -Value $ESXiService.Policy
                    $ServiceStatus | add-member -type NoteProperty -Name sfcbd_CurrentStatus -Value $ServiceState
                }
        }
		
		if ($slpdfound -eq "Yes")
		{
			if ( ($ServiceStatus.slpd_StartupPolicy -eq "off") -and ($ServiceStatus.slpd_CurrentStatus -eq "stopped") -and ($ServiceStatus.sfcbd_StartupPolicy -eq "off") -and ($ServiceStatus.sfcbd_CurrentStatus -eq "stopped") )
			{
				$vmsacompliant = "Yes"
			}
		} elseif ($slpdfound -eq "No"){
			echo "Here"
			$vmsacompliant = "SLP service needs to be checked/set manually"
		}
    $ServiceStatus | add-member -type NoteProperty -Name VMSA-2021-0014_Compliant -Value $vmsacompliant
    
    $VMSAServiceStatus+=$ServiceStatus
	$slpdfound = "No"
    }


#Export Result
$ResultFilename = "C:\Temp\ESXiServiceStatus_Post_Disable.csv"

try
{
    $VMSAServiceStatus | export-csv $ResultFilename -notype -ErrorAction Stop
    Write-Host "Please check the final result file - " + $ResultFilename
}

catch
{
    $ResultFilename = "ESXiServiceStatus_Post_Disable" + (Get-Date).tostring("dd-MM-yyyy-hh-mm-ss") + ".csv"
    $VMSAServiceStatus | export-csv $ResultFilename -notype
    $result = Get-Item $ResultFilename
    Write-Host "Please check the final result file saved in current directory - " $result.fullname
}

$VCConnection = Disconnect-VIServer -Server $vcenter -confirm:$false