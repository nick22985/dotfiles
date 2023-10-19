# cmd /V /C "curl -o script.ps1 https://raw.githubusercontent.com/nick22985/dotfiles/master/scripts/setup.ps1 & powershell.exe -ExecutionPolicy Bypass -File script.ps1"

# Check for admin privileges
if(!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
	Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`"  `"$($MyInvocation.MyCommand.UnboundArguments)`""
	Exit
}

# Install winget
$hasPackageManager = Get-AppPackage -name 'Microsoft.DesktopAppInstaller'

if(!$hasPackageManager)
{
    Add-AppxPackage -Path 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'

    $releases_url = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $releases = Invoke-RestMethod -uri $releases_url
    $latestRelease = $releases.assets | Where { $_.browser_download_url.EndsWith('msixbundle') } | Select -First 1

    "Installing winget from $($latestRelease.browser_download_url)"
    Add-AppxPackage -Path $latestRelease.browser_download_url
}

# Running as admin puts us in C:\Windows\System32 by default so we need to change to the user's home directory
Set-Location -Path "$env:USERPROFILE"

winget install -e --id=Git.Git --force

if (Test-Path -Path "$env:userprofile\.dotfiles" -PathType Container) {
	Write-Host ".dotfiles already exists"
} else {
	Write-Host ".dotfiles does not exists"
	git clone --bare git@github.com:nick22985/dotfiles.git $HOME/.dotfiles
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

config checkout

config submodule update --init --recursive

config config status.showUntrackedFiles no

# Run install script
Invoke-Expression "$env:USERPROFILE/install/OS/windows/install.ps1"
