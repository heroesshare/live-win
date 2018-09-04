#
# Copyright Heroes Share
# https://heroesshare.net
#

# Stop on all errors
$ErrorActionPreference = "Stop"

$AppDir = [Environment]::GetFolderPath('ApplicationData') + "\Heroes Share"
$LogFile = "$AppDir\updater.log"

# Add timestamps to transcript log outputs
filter LogLine {"[$(Get-Date -Format u)] $_"}

# Make sure application directory exists
if ( -not (Test-Path "$AppDir" -PathType Container) ) {
	Start-Transcript -Path "$LogFile" -Append
	Write-Output "Application directory missing: '$AppDir'. Quitting." | LogLine
	Stop-Transcript
	
	exit 1
}

# Check for version.txt
if ( -not ( Test-Path "$AppDir\version.txt" -PathType Leaf ) ) {
	$Installed = "0.0.0000"
} else {
	# Get local version
	$Installed = Get-Content "$AppDir\version.txt" -Raw 
}

# Get latest version from the website
$Latest = Invoke-RestMethod -Uri "https://heroesshare.net/clients/check/win"

if ( -not ("$Latest") -Or "$Latest" -eq "error" ) {
	Start-Transcript -Path "$LogFile" -Append
	Write-Output "Error loading version from website." | LogLine
	Stop-Transcript
	
	exit 2
}

# Compare versions
if ( "$Latest" -eq "$Installed" ) {
	exit 0
}

# Start logging
Start-Transcript -Path "$LogFile" -Append

Write-Output "Latest version $Latest differs from current $Installed" | LogLine

# Download latest installer
$TmpFile = New-TemporaryFile

$client = New-Object System.Net.WebClient
$client.DownloadFile("https://heroesshare.net/clients/update/win", $TmpFile)

Write-Output "Download complete: $TmpFile"

# Get correct hash from website
$Hash = Invoke-RestMethod -Uri "https://heroesshare.net/clients/hash/win"

# test it against download
$Test = (Get-FileHash $TmpFile.FullName -Algorithm MD5).Hash.ToLower()

if ( "$Test" -ne "$Hash" ) {
	Write-Output "Hash on downloaded file is incorrect:" | LogLine
	Write-Output "$Test versus $Hash" | LogLine
	
	Remove-Item -Force "$TmpFile"
	Stop-Transcript
	
	exit 3
}

# Expand the archive
Rename-Item -Path "$TmpFile" -NewName "$($TmpFile).zip"
$TmpDir = Split-Path -Resolve -Path "$($TmpFile).zip"
Expand-Archive "$($TmpFile).zip" -DestinationPath "$TmpDir\HeroesShareLive" -Force

Remove-Item -Force "$($TmpFile).zip"

# Verify extraction
if ( -not ( Test-Path "$TmpDir\HeroesShareLive\Setup.bat" -PathType Leaf ) ) {
	Write-Output "Archive missing Setup.bat. Try a manual update:" | LogLine
	Write-Output "https://heroesshare.net/clients/install/win" | LogLine
	Stop-Transcript

	exit 4
}

# Run Setup.bat
& "$TmpDir\HeroesShareLive\Setup.bat"
$Result = $LastExitCode

Remove-Item "$TmpDir\HeroesShareLive" -Force -Recurse

# Verify installer succeeded
if ( $Result -ne 0 ) {
	Write-Output "Installation failed. Try a manual update:" | LogLine
	Write-Output "https://heroesshare.net/clients/install/win" | LogLine
	exit 5
}

# Confirm new version
$Installed = Get-Content "$AppDir\version.txt" -Raw
if ( "$Latest" -ne "$Installed" ) {
	Write-Output "Installation complete but version mismatch. Try a manual update:"
	Write-Output "https://heroesshare.net/clients/install/win"
	exit 6
}

Write-Output "Installation complete! Updated to $Latest"

# Stop logging
Stop-Transcript

exit 0
