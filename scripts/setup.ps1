# cmd /V /C "curl -o script.ps1 https://raw.githubusercontent.com/nick22985/dotfiles/master/scripts/install.ps1 & powershell.exe -ExecutionPolicy Bypass -File script.ps1"

# Check for admin privileges
if(!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
	Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`"  `"$($MyInvocation.MyCommand.UnboundArguments)`""
	Exit
}

# Running as admin puts us in C:\Windows\System32 by default so we need to change to the user's home directory
Set-Location -Path "$env:USERPROFILE"

winget install -e --id=Git.Git

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

. $PROFILE

config checkout

config submodule update --init --recursive

config config status.showUntrackedFiles no

# Run install script
Invoke-Expression "$env:USERPROFILE/install/OS/windows/install.ps1"
