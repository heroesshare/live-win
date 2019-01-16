#
# Build 1.5
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
	
	# Check for sound preference
	if ( -not (Test-Path "$AppDir\EnableSound.txt" -PathType Leaf) ) {
		return $True
	}

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

# Check for version.txt
if ( -not ( Test-Path "$AppDir\version.txt" -PathType Leaf ) ) {
	$Version = "0.0.0000"
} else {
	# Get local version
	$Version = Get-Content "$AppDir\version.txt" -Raw 
}

# Record process ID
Write-Output "$pid" > "$PidFile"
Write-Output "Launching version $Version with process ID $Pid..." | LogLine

$LobbyPath = [System.IO.Path]::GetTempPath() + "Heroes of the Storm\"
Write-Output "BattleLobby Path = $LobbyPath" | LogLine

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
	$LobbyFile = $null
	$RejoinFile = $null

	# make sure the directory exists (sometimes cleared between game launches)
	if ( (Test-Path "$LobbyPath" -PathType Container) ) {
		# Look for any new BattleLobby files and grab the latest one
		Try {
			$LobbyFile = Get-ChildItem -File -Recurse -Filter "replay.server.battlelobby" -Path $LobbyPath | Where-Object {$_.LastWriteTime -gt (Get-Item -Path "$AppDir\LastMatch").LastWriteTime} | Sort-Object LastAccessTime -Descending | Select-Object -First 1
		} Catch {
			$ErrorMessage = $_.Exception.Message
			Write-Output "Failed to watch for BattleLobby: $ErrorMessage" | LogLine
			Start-Sleep 30
		}
	}
	
	# If there was a match, post it to the server
	if ($LobbyFile) {
		Write-Output "Detected new battle lobby file: $($LobbyFile.FullName)" | LogLine

		# Update status
		(Get-Item -Path "$AppDir\LastMatch").LastWriteTime = Get-Date
				
		# Get hash to check if it has been uploaded
		$UploadHash = (Get-FileHash $LobbyFile.FullName -Algorithm MD5).Hash.ToLower()
		$Result = Invoke-RestMethod -Uri "https://heroesshare.net/lives/check/$UploadHash"
		
		if ( ! "$Result" ) {
			Write-Output "Uploading lobby file with hash $UploadHash... " | LogLine
			$Result = Invoke-MultiPart -Uri "https://heroesshare.net/lives/battlelobby/$RandID" -Field "upload" -Path $LobbyFile.FullName
			Write-Output $Result.Result | LogLine

			# Audible notification when complete
			Play-Sound -Status "SUCCESS"
			
			
			# Watch for new rejoin file - should be about 1 minute but wait up to 5
			Write-Output "Waiting for rejoin file in $RejoinPath..." | LogLine
			$i = 0
			while ( $i -lt 60 ) {
				if ( (Test-Path "$RejoinPath" -PathType Container) ) {
					Try {
						$RejoinFile = Get-ChildItem -File -Recurse -Filter "*.StormSave" -Path $RejoinPath | Where-Object {$_.LastWriteTime -gt (Get-Item -Path "$AppDir\LastRun").LastWriteTime} | Sort-Object LastAccessTime -Descending | Select-Object -First 1
					}  Catch {
						$ErrorMessage = $_.Exception.Message
						Write-Output "Failed to watch for rejoin file: $ErrorMessage" | LogLine
						Start-Sleep 30
		
						$RejoinFile = $null
					}
				} else {
					$RejoinFile = $null
				}
				
				# If there was a match, post it to the server
				if ( "$RejoinFile" ) {
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

					# Start watching for talents (until game over)
					$TrackerHash = $null
					$TalentsHash = $null
					$GameOver = 0

					# Watch for up to 20 minutes at a time
					$j = 0
					$TrackerPath = Split-Path -Path $LobbyFile.FullName -Parent
					$TrackerFile = Join-Path $TrackerPath "replay.tracker.events"

					Write-Output "Begin watching for talents, monitoring $TrackerFile" | LogLine
					while ( $j -lt 40 ) {
						
						# If file is gone, game is over
						if ( -not ( Test-Path $TrackerFile -PathType Leaf ) ) {
							Write-Output "Tracker events file no longer available: $TrackerFile; completing." | LogLine

							$GameOver = 1
							break
						} else {
							# Get updated hash of tracker file
							Try {
								$TmpHash = (Get-FileHash $TrackerFile -Algorithm MD5).Hash.ToLower()

							# If file is in use, game is still going
							} Catch {
								$TmpHash = -Join ((0..9) + $Lowers + (0..9) + $Lowers + (0..9) + $Lowers | Get-Random -Count 24)
							}

							# If file stayed the same, game is over
							if ( "$TmpHash" -eq "$TrackerHash" ) {
								Write-Output "No updates to tracker events file; completing." | LogLine
								$GameOver = 1
								break

							# Game still going
							} else {
								# Update last hash
								$TrackerHash = "$TmpHash"
								
								# Check for new talents
								& "$Parser" --gameevents --json "$($RejoinFile.FullName)" | Select-String -Pattern "SHeroTalentTreeSelectedEvent" > "$TmpFile"
								$TmpHash = (Get-FileHash $TmpFile.FullName -Algorithm MD5).Hash.ToLower()
								
								# If file was different than last run, upload it
								if ( "$TmpHash" -ne "$TalentsHash" ) {
									# Update last hash
									$TalentsHash = "$TmpHash"

									Write-Output "Uploading game events file... " | LogLine
									$Result = Invoke-MultiPart -Uri "https://heroesshare.net/lives/gameevents/$RandID" -Field "upload" -Path $TmpFile.FullName
									Write-Output $Result.Result | LogLine
									
									# Reset the timer
									$j = 0
								}

								# Wait a while then try again
								$j++
								Start-Sleep 30
							}
						}
					}
					
					if ( $GameOver -ne 1 ) {
						Write-Output "Error: Timed out waiting for game to finish" | LogLine
					}
					
					# Wait for post-game cleanup
					Start-Sleep 10
					
					# Check for a new replay file
					$ReplayFile = Get-ChildItem -File -Recurse -Filter "*.StormReplay" -Path $RejoinPath | Where-Object {$_.LastWriteTime -gt (Get-Item -Path "$AppDir\LastMatch").LastWriteTime} | Sort-Object LastAccessTime -Descending | Select-Object -First 1

					# If there was a match, post it to the server
					if ( "$ReplayFile" ) {
						Write-Output "Detected new replay file: $($ReplayFile.FullName)" | LogLine
						Write-Output "Uploading replay file (includes HotsApi and HotsLogs)... " | LogLine
						#Invoke-MultiPart -Uri "http://hotsapi.net/api/v1/upload?uploadToHotslogs=1" -Field "file" -Path $ReplayFile.FullName > $TmpFile
						#cat $TmpFile | LogLine
						
						# Notify of completion and upload status
						$Result = Invoke-MultiPart -Uri "https://heroesshare.net/lives/complete/$RandID" -Field "upload" -Path $ReplayFile.FullName
						Write-Output $Result.Result | LogLine
									
						# Audible notification when complete
						Play-Sound -Status "SUCCESS"
					} else {
						# notify of completion
						$Result = Invoke-RestMethod -Uri "https://heroesshare.net/lives/complete/$RandId"
						
						Write-Output "Unable to locate replay file for recent live game!" | LogLine
						Play-Sound -Status "FAILURE"
					}
										
					# clean up and pass back to main watch loop
					Remove-Item -Force "$TmpFile"
					$LobbyFile = ""
					break;
				}
				
				$i++
				Start-Sleep 5
			} #endwhile
			
			# check if stage 2 uploads succeeded or timed out
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
		$LobbyFile = ""
		
		Write-Output "Resume watching for live games in $LobbyPath..." | LogLine
	}
	
	# note this cycle
	(Get-Item -Path "$AppDir\LastRun").LastWriteTime = Get-Date
	Start-Sleep 5

}

# Stop logging
Stop-Transcript
