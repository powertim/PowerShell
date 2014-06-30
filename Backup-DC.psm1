# PowerShell Module to backup a Microsoft Active Directory Domain Controller from Windows Server 2008 and later.
# Provide a modular conservation of the backups (not available by default withtout scripting).

Function Backup-DC
{
[CmdletBinding()] 
	Param 
	(
	[Parameter(Position=0, Mandatory=$true)]
	[String]$serverName,
	[Parameter(Position=1, Mandatory=$false)]
	[String]$targetServer = "mynas.dom",
	[Parameter(Position=2, Mandatory=$true)]
	[String]$targetShare = "\\mynas.dom\BACKUP_DC",
	[Parameter(Position=3, Mandatory=$true)]
	[String]$account,
	[Parameter(Position=4, Mandatory=$true)]
	[Int]$conservation,
	[Parameter(Position=5, Mandatory=$false)]
	[Bool]$mail
	)
	
	Process
	{
  	$os = (Get-WmiObject Win32_OperatingSystem).Caption
  	$domain = (Get-WmiObject Win32_ComputerSystem).Domain
  
  	Switch -wildcard ($domain)
  	{
    	"usa.dom" 	{$site = "US"}
    	"france.local" 	{$site = "FR"}
	  }
	
$sender = $serverName + "@" + $domain
$encodingMail = [System.Text.Encoding]::UTF8

		If ($os -cnotlike "*Server*")
		{
		  Write-Host "$os is not supported by this function !" -ForegroundColor Red
		}
		Else
		{
		Import-Module ServerManager | Out-Null
		
			If ((Get-WindowsFeature -Name Backup-Features).Installed -eq $false)
			{
  			Write-Host "Backup-Features are not available on this server, the installation is starting..." -ForegroundColor DarkYellow
  			Add-WindowsFeature -Name Backup-Features -IncludeAllSubFeature
  		}
			
			Get-PSSnapin Windows.ServerBackup -ErrorVariable $snapinError -ErrorAction SilentlyContinue | Out-Null
			
			If($snapinError -ne $null)
			{
  			Add-PSSnapin Windows.ServerBackup | Out-Null
			}
		
		Try
		{
  		$socket = New-Object Net.Sockets.TcpClient
  		$socket.Connect($targetServer, 445)
		}
		Catch
		{
		  Write-Host "$targetServer is not available on CIFS !" -ForegroundColor Red
		}
			
			$serverName = $serverName.ToUpper()
			$targetFolder = $targetShare + "\" + $serverName
			
				If (!(Test-Path -Path $targetFolder))
				{
				  New-Item -ItemType Directory -Path $targetFolder | Out-Null
				}
			
			$backupFolder = $targetFolder + "\" + (Get-Date).ToString("yyyy-MM-dd")
			
				If (!(Test-Path -Path $backupFolder))
				{
					New-Item -ItemType Directory -Path $backupFolder | Out-Null
				}
			
			$policy = New-WBPolicy
			$volume = Get-WBVolume -VolumePath C: 
			
			Add-WBVolume -Policy $policy -Volume $volume
			Add-WBSystemState $policy 
			Add-WBBareMetalRecovery $policy 
			
			$backupTarget = New-WBBackupTarget -NetworkPath $backupFolder
			
			Add-WBBackupTarget -Policy $policy -Target $backupTarget -WarningAction SilentlyContinue
			Set-WBVssBackupOptions -Policy $policy -VssFullBackup
			Start-WBBackup -Policy $policy -Force -ErrorVariable $wbBackupError
			
				If ($wbBackupError -ne $null)
				{
					$body = "BACKUP FAILED ON $serverName`n`r`n`rThe backup job of the DC failed with the following error message :`r`n`r`n$wbBackupError`r`n`r`nPlease try to relaunch the job manually. `r`n`r`nIn case of repeated errors, please contact support@mycompany.com."
					Send-MailMessage -From $sender -To "backups@mycompany.com" -Subject "[$site][BACKUP] - Failure on $serverName !" -Body $body -SmtpServer "smtp.cppg.dom" -Encoding $encodingMail
				}
			
			$backupNumber = (Get-ChildItem -Path $targetFolder| Where-Object {$_.PSIsContainer -eq $true}).Count
			
			If ($backupNumber -gt $conservation)
			{
				$oldBackups = Get-ChildItem -Path $targetFolder| Where-Object {$_.PSIsContainer -eq $true} | Sort-Object -Property Name -Descending | Select-Object -Last ($backupNumber - $conservation)
			
				Foreach ($oldBackup in $oldBackups)
				{
					Remove-Item -Path $oldBackups.FullName -Force -Recurse -Confirm:$false
				}
			}
			
			$body = "BACKUP SUCCEEDED ON $serverName`n`r`n`rThe backup job of the DC was successfully completed.`r`nThe files are available into the followind folder : $backupFolder. `r`n`r`nYour infrastructure team. "
			Send-MailMessage -From $sender -To "backups@mycompany.com" -Subject "[$site][BACKUP] - Success on $serverName !" -Body $body -SmtpServer "smtp.mydomain.dom" -Encoding $encodingMail		
		}
	}
}
