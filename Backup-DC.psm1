# PowerShell Module to backup a Microsoft Active Directory Domain Controller from Windows Server 2008 and later.
# Provide a modular conservation of the backups (not available by default without scripting).

Function Backup-DC
{
	[CmdletBinding()] 
	Param 
	(
	[Parameter(Position=0, Mandatory=$true)]
	[String]$serverName,
	[Parameter(Position=1, Mandatory=$false)]
	[String]$targetServer = "mycompany.dom",
	[Parameter(Position=2, Mandatory=$true)]
	[String]$targetShare = "\\mycompany.dom\BACKUP_DC",
	[Parameter(Position=3, Mandatory=$true)]
	[Int]$conservation,
	[Parameter(Position=4, Mandatory=$false)]
	[Bool]$mail
	)
	
	Process
	{
		# Get the OS name to check the compatibility
		$os = (Get-WmiObject Win32_OperatingSystem).Caption
		# Get the domain name
		$domain = (Get-WmiObject Win32_ComputerSystem).Domain
	  	
	  	# Optional switch to add the location into the mail's subject
	  	Switch -wildcard ($domain)
	  	{
			"*usa.dom" 		{$site = "US"}
			"*france.local" {$site = "FR"}
		}
		
		# Create the mail address of the sender
		$sender = $serverName + "@" + $domain
		# Create the encoding object (useful to create the body of the mail)
		# You can select any available encoding method
		$encodingMail = [System.Text.Encoding]::UTF8
		
		# Just a check for dummies
		# You can improve it with a wildcard switch who lists the different OS (works from Server 2008)
		If ($os -cnotlike "*Server*")
		{
			Write-Host "$os is not supported by this function !" -ForegroundColor Red
		}
		Else
		{	
			# Check the availability of the backup features
			Import-Module ServerManager | Out-Null
			
			If ((Get-WindowsFeature -Name Backup-Features).Installed -eq $false)
			{
	  			Write-Host "Backup-Features are not available on this server, the installation is starting..." -ForegroundColor DarkYellow
	  			# We start the installation of the feature
	  			Add-WindowsFeature -Name Backup-Features -IncludeAllSubFeature
	  		}
			
			# Try to import the PSSnapin into the current session
			Get-PSSnapin Windows.ServerBackup -ErrorVariable $snapinError -ErrorAction SilentlyContinue | Out-Null
				
			If($snapinError -ne $null)
			{
	  			# Import the PSSnapin
	  			Add-PSSnapin Windows.ServerBackup | Out-Null
			}
			
			# Check the availabilty of CIFS on $targetServer
			Try
			{
		  		$socket = New-Object Net.Sockets.TcpClient
		  		$socket.Connect($targetServer, 445)
			}
			Catch
			{
			  	Write-Host "$targetServer is not available on CIFS !" -ForegroundColor Red
			}
			
			# Just esthetic	
			$serverName = $serverName.ToUpper()
			# Define the backup location defined by $serverName
			$targetFolder = $targetShare + "\" + $serverName
			
			# Check the existence of the target location	
			If (!(Test-Path -Path $targetFolder))
			{
				# Folder creation
				New-Item -ItemType Directory -Path $targetFolder | Out-Null
			}
			
			# Define the target folder defined by the current date	
			$backupFolder = $targetFolder + "\" + (Get-Date).ToString("yyyy-MM-dd")
				
			If (!(Test-Path -Path $backupFolder))
			{
				# Folder creation
				New-Item -ItemType Directory -Path $backupFolder | Out-Null
			}
			
			# Create the backup policy	
			$policy = New-WBPolicy
			# Define the volume to capture
			$volume = Get-WBVolume -VolumePath C: 
			# Add the volume to WBAdmin	
			Add-WBVolume -Policy $policy -Volume $volume
			# Add the system state
			Add-WBSystemState $policy
			# Add the BMR
			Add-WBBareMetalRecovery $policy 
			# Define the target
			$backupTarget = New-WBBackupTarget -NetworkPath $backupFolder
			# Add the target to WBAdmin	
			Add-WBBackupTarget -Policy $policy -Target $backupTarget -WarningAction SilentlyContinue
			# Configure VSS options for WBAdmin
			Set-WBVssBackupOptions -Policy $policy -VssFullBackup
			# Start the backup job
			Start-WBBackup -Policy $policy -Force -ErrorVariable $wbBackupError
			
			# Send a mail in case of error	
			If ($wbBackupError -ne $null)
			{
				$body = "BACKUP FAILED ON $serverName`n`r`n`rThe backup job of the DC failed with the following error message :`r`n`r`n$wbBackupError`r`n`r`nPlease try to relaunch the job manually. `r`n`r`nIn case of repeated errors, please contact support@mycompany.com."
				Send-MailMessage -From $sender -To "backups@mycompany.com" -Subject "[$site][BACKUP] - Failure on $serverName !" -Body $body -SmtpServer "smtp.cppg.dom" -Encoding $encodingMail
			}
			
			# Count the number of backups present into $targetFolder	
			$backupNumber = (Get-ChildItem -Path $targetFolder| Where-Object {$_.PSIsContainer -eq $true}).Count
			
			# If greater than $conservation the purge is launched	
			If ($backupNumber -gt $conservation)
			{
				# Sort the folders by date (the last one is the oldest)
				$oldBackups = Get-ChildItem -Path $targetFolder| Where-Object {$_.PSIsContainer -eq $true} | Sort-Object -Property Name -Descending | Select-Object -Last ($backupNumber - $conservation)
				
				# Delete all the old backups
				Foreach ($oldBackup in $oldBackups)
				{
					Remove-Item -Path $oldBackups.FullName -Force -Recurse -Confirm:$false
				}
			}
			
			# Send a mail of success	
			$body = "BACKUP SUCCEEDED ON $serverName`n`r`n`rThe backup job of the DC was successfully completed.`r`nThe files are available into the following folder : $backupFolder. `r`n`r`nYour infrastructure team. "
			Send-MailMessage -From $sender -To "backups@mycompany.com" -Subject "[$site][BACKUP] - Success on $serverName !" -Body $body -SmtpServer "smtp.mydomain.dom" -Encoding $encodingMail		
		}
	}
}
