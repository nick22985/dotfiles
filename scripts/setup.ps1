# cmd /V /C "curl -o script.ps1 https://raw.githubusercontent.com/nick22985/dotfiles/master/scripts/setup.ps1 & powershell.exe -ExecutionPolicy Bypass -File script.ps1"

# Check for admin privileges
if(!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
	Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`"  `"$($MyInvocation.MyCommand.UnboundArguments)`""
	Exit
}
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "winget is installed."
} else {
	Write-Host "winget is not installed."
	# Install winget
	Write-Information "Downloading WinGet and its dependencies..."
	Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
	Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile Microsoft.VCLibs.x64.14.00.Desktop.appx
	Invoke-WebRequest -Uri https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx -OutFile Microsoft.UI.Xaml.2.7.x64.appx
	Add-AppxPackage Microsoft.VCLibs.x64.14.00.Desktop.appx
	Add-AppxPackage Microsoft.UI.Xaml.2.7.x64.appx
	Add-AppxPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
 	Remove-Item Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
  	Remove-Item Microsoft.UI.Xaml.2.7.x64.appx
   	Remove-Item Microsoft.VCLibs.x64.14.00.Desktop.appx
}

# Running as admin puts us in C:\Windows\System32 by default so we need to change to the user's home directory
Set-Location -Path "$env:USERPROFILE"

winget install -e --id=Git.Git --force

# Ensure the directory path exists
$directory = [System.IO.Path]::GetDirectoryName($PROFILE)
if (-not (Test-Path -Path $directory)) {
    New-Item -ItemType Directory -Path $directory -Force
}

# Create the profile file if it doesn't exist
if (-not (Test-Path -Path $PROFILE)) {
    # You can use New-Item to create the file, and you can add content to it if needed.
    New-Item -Path $PROFILE -ItemType File
}

$USERPROFILE = Get-Content $PROFILE

$configFunction = 'function config {& "$env:ProgramFiles\Git\bin\git.exe" --git-dir="$env:userprofile/.dotfiles/" --work-tree="$env:userprofile/" $args}'

if ($USERPROFILE -contains $configFunction) {
	Write-host "config function already exists"
} else {
	Write-host "Installing config function"
	Add-Content -Path $PROFILE -Value "`n$configFunction"
}
# Refreshes the path variable without needing to restart powershell
$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

. $PROFILE

if (Test-Path -Path "$env:userprofile\.dotfiles" -PathType Container) {
	Write-Host ".dotfiles already exists"
} else {
	Write-Host ".dotfiles does not exists"
	git clone --bare git@github.com:nick22985/dotfiles.git $HOME/.dotfiles
}
config checkout

config submodule update --init --recursive

config config status.showUntrackedFiles no

# Run install script
Invoke-Expression "$env:USERPROFILE/install/OS/windows/install.ps1"
