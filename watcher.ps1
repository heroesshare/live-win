#
# Version 1.0
# Copyright Heroes Share
# https://heroesshare.net
#

# Stop on all errors
$ErrorActionPreference = "Stop"

# force multipart file upload
# https://stackoverflow.com/a/45409728
Function Invoke-MultiPart {
	Param ([string] $Uri, [string] $Field, [string] $Path)

	Try {
		
		Add-Type -AssemblyName 'System.Net.Http'

		$Client = New-Object System.Net.Http.HttpClient
		$Content = New-Object System.Net.Http.MultipartFormDataContent
		$FileStream = [System.IO.File]::OpenRead($Path)
		$FileName = [System.IO.Path]::GetFileName($Path)
		$FileContent = New-Object System.Net.Http.StreamContent($FileStream)
		$Content.Add($FileContent, $Field, $FileName)

		$Result = $Client.PostAsync($Uri, $Content).Result
		$Result.EnsureSuccessStatusCode()
		
		return $Result.Content.ReadAsStringAsync()
	}
	Catch {
		Write-Error $_
		exit 1
	}
	Finally {
		if ($Client -ne $null) { $Client.Dispose() }
		if ($Content -ne $null) { $Content.Dispose() }
		if ($FileStream -ne $null) { $FileStream.Dispose() }
		if ($FileContent -ne $null) { $FileContent.Dispose() }
	}
}

# Play a sound based off a given status
Function Play-Sound {
	Param ([string] $Status)
	
	Switch ($Status) {
		"SUCCESS" {
			$Path = "C:\Windows\Media\Alarm02.wav"
			$FallBack = [System.Media.SystemSounds]::Hand
		}
		
		"FAILURE" {
			$Path = "C:\Windows\Media\ringout.wav"
			$FallBack = [System.Media.SystemSounds]::Exclaimation
		}
		
		default {
			$Path = $null
			$FallBack = [System.Media.SystemSounds]::Question
		}
	}
	
	# Make sure sound file is availalbe
	if ( Test-Path "$Path" -PathType Leaf ) {
		$Sound = new-Object System.Media.SoundPlayer;
		$Sound.SoundLocation = $Path;
		$Sound.Play();
	
	# If media file wasn't found use fallback sound
	} Else {
		$FallBack.play()
	}
}

$AppDir = [Environment]::GetFolderPath('ApplicationData') + "\Heroes Share"
$Parser = "$AppDir\rejoinprotocol.exe"
$PidFile = "$AppDir\watcher.pid"
$LogFile = "$AppDir\watcher.log"


# Add timestamps to transcript log outputs
filter LogLine {"[$(Get-Date -Format u)] $_"}

# Make sure application directory exists
if ( -not (Test-Path "$AppDir" -PathType Container) ) {
	Write-Output "Application directory missing: '$AppDir'. Quitting." | LogLine
	exit 1
}

# Start logging
Start-Transcript -Path "$LogFile" -Append

# Make sure parser exists
if ( -not (Test-Path "$Parser" -PathType Leaf) ) {
	Write-Output "Parsing protocol missing: '$Parser'. Quitting." | LogLine
	exit 2
}

# Record process ID
Write-Output "$pid" > "$PidFile"
Write-Output "Launching with process ID $Pid..." | LogLine

$BattleLobbyPath = [System.IO.Path]::GetTempPath() + "Heroes of the Storm\"
Write-Output "BattleLobby Path = $BattleLobbyPath" | LogLine

$RejoinPath = [Environment]::GetFolderPath("MyDocuments") + "\Heroes of the Storm\Accounts\"
Write-Output "Rejoin Path = $RejoinPath" | LogLine

# Construct the random ID
$Lowers = 97..102 | ForEach-Object {[Char]$PSItem}
$RandID = -Join ((0..9) + $Lowers + (0..9) + $Lowers + (0..9) + $Lowers | Get-Random -Count 24)
Write-Output "Random ID = $RandID" | LogLine

# check for lastmatch file
if ( -not (Test-Path "$AppDir\LastMatch" -PathType Leaf) ) {
	Write-Output "Last match file missing; creating a fresh copy" | LogLine
	$null > "$AppDir\LastMatch"
	$null > "$AppDir\LastRun"
}

# Main process loop
while($true) {
	$ReplayFile = $null
	$RejoinFile = $null

	# make sure the directory exists (sometimes cleared between game launches)
	if ( (Test-Path "$BattleLobbyPath" -PathType Container) ) {
		# Look for any new BattleLobby files and grab the latest one
		Try {
			$ReplayFile = Get-ChildItem -File -Recurse -Filter "replay.server.battlelobby" -Path $BattleLobbyPath | Where-Object {$_.LastWriteTime -gt (Get-Item -Path "$AppDir\LastMatch").LastWriteTime} | Sort-Object LastAccessTime -Descending | Select-Object -First 1
		} Catch {
			$ErrorMessage = $_.Exception.Message
			Write-Output "Failed to watch for BattleLobby: $ErrorMessage" | LogLine
			Start-Sleep 30
		}
	} else {
	
	}	
	# If there was a match, post it to the server
	if ($ReplayFile) {
		Write-Output "Detected new battle lobby file: $($ReplayFile.FullName)" | LogLine

		# Update status
		(Get-Item -Path "$AppDir\LastMatch").LastWriteTime = Get-Date

		# Get hash to check if it has been uploaded
		$Hash = (Get-FileHash $ReplayFile.FullName -Algorithm MD5).Hash.ToLower()
		$Result = Invoke-RestMethod -Uri "https://heroesshare.net/lives/check/$Hash"
		
		if ( ! "$Result" ) {
			Write-Output "Uploading replay file with hash $Hash... " | LogLine
			$Result = Invoke-MultiPart -Uri "https://heroesshare.net/lives/battlelobby/$RandID" -Field "upload" -Path $ReplayFile.FullName
			Write-Output $Result.Result | LogLine

			# Audible notification when complete
			Play-Sound -Status "SUCCESS"
			
			
			# Watch for new rejoin file - should be about 1 minute but wait up to 5
			$i = 0
			while ( $i -lt 60 ) {
				Try {
					$RejoinFile = Get-ChildItem -File -Recurse -Filter "*.StormSave" -Path $RejoinPath | Where-Object {$_.LastWriteTime -gt (Get-Item -Path "$AppDir\LastRun").LastWriteTime} | Sort-Object LastAccessTime -Descending | Select-Object -First 1
				}  Catch {
					$ErrorMessage = $_.Exception.Message
					Write-Output "Failed to watch for rejoin file: $ErrorMessage" | LogLine
					Start-Sleep 30
		
					$RejoinFile = $null
				}
				
				# If there was a match, post it to the server
				if ($RejoinFile) {
					Write-Output "Detected new rejoin file: $($RejoinFile.FullName)" | LogLine

					# Grab a temp file
					$TmpFile = New-TemporaryFile
					$ParseFlag = $false
					
					# Parse details from the file
					& "$Parser" --details --json "$($RejoinFile.FullName)" > "$TmpFile"
					if ( $LastExitCode -eq 0 ) {		
						Write-Output "Uploading details file... " | LogLine
						$Result = Invoke-MultiPart -Uri "https://heroesshare.net/lives/details/$RandID" -Field "upload" -Path $TmpFile.FullName
						Write-Output $Result.Result | LogLine
						
					} else {
						Write-Output "Unable to parse details from rejoin file" | LogLine
						$ParseFlag = $true
					}
					
					# Parse attribute events from the file
					& "$Parser" --attributeevents --json "$($RejoinFile.FullName)" > "$TmpFile"
					if ( $LastExitCode -eq 0 ) {		
						Write-Output "Uploading attribute events file... " | LogLine
						$Result = Invoke-MultiPart -Uri "https://heroesshare.net/lives/attributeevents/$RandID" -Field "upload" -Path $TmpFile.FullName
						Write-Output $Result.Result | LogLine
						
					} else {
						Write-Output "Unable to parse attribute events from rejoin file" | LogLine
						$ParseFlag = $true
					}
					
					# Parse init data from the file
					& "$Parser" --initdata --json "$($RejoinFile.FullName)" > "$TmpFile"
					if ( $LastExitCode -eq 0 ) {		
						Write-Output "Uploading init data file... " | LogLine
						$Result = Invoke-MultiPart -Uri "https://heroesshare.net/lives/initdata/$RandID" -Field "upload" -Path $TmpFile.FullName
						Write-Output $Result.Result | LogLine
						
					} else {
						Write-Output "Unable to parse init data from rejoin file" | LogLine
						$ParseFlag = $true
					}
					
					
					if ( $ParseFlag ) {
						# Audible notification of failure
						Play-Sound -Status "FAILURE"
					} else {
						# Audible notification when all complete
						Play-Sound -Status "SUCCESS"
					}
					
					Remove-Item -Force "$TmpFile"
					break;
				}
				
				$i++
				Start-Sleep 5
			} #endwhile
			
			# check if this was a match or a timeout
			if ( ! "$RejoinFile" ) {
				Write-Output "No rejoin file found for additional upload: $RejoinPath" | LogLine

				# Audible notification of failure
				Play-Sound -Status "FAILURE"
			}
			$RejoinFile = ""
			
		# hash check returned data
		} else {
			Write-Output $Result | LogLine
			
			# Audible notification of failure
			Play-Sound -Status "FAILURE"
		}
		$ReplayFile = ""
	}
	
	# note this cycle
	(Get-Item -Path "$AppDir\LastRun").LastWriteTime = Get-Date
	Start-Sleep 5

}

# Stop logging
Stop-Transcript
