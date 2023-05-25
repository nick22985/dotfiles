# cmd /V /C "curl -o script.ps1 https://raw.githubusercontent.com/nick22985/dotfiles/master/install/scripts/install.ps1 & powershell.exe -ExecutionPolicy Bypass -File script.ps1"

# Check for admin privileges
# if(!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
# 	Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`"  `"$($MyInvocation.MyCommand.UnboundArguments)`""
# 	Exit
# }
# Install git first
# winget install -e --id=Git.Git

if ([System.IO.File]::Exists("$env:userprofile/.dotfiles/")-ne $true) {
	Write-Host "File does not exist"
	git clone --bare git@github.com:nick22985/dotfiles.git $HOME/.dotfiles
} else {
	Write-Host ".dotfiles already exists"
}

$USERPROFILE = Get-Content $PROFILE

$checkConfig = '& "$env:ProgramFiles\Git\bin\git.exe" --git-dir="$env:userprofile/.dotfiles/" --work-tree="$env:userprofile/" $args'

$configFunction = "function config {$checkConfig}"

if ($USERPROFILE -contains $checkConfig) {
	Write-host "config function already exists"
} else {
	Write-host "Installing config function"
	Add-Content -Path $PROFILE -Value $configFunction
}

. $PROFILE

config checkout

config submodule update --init --recursive

config config status.showUntrackedFiles no


# https://gist.githubusercontent.com/nick22985/0115e0504e3a35d6a8fb06c39d6d1a38/raw/d5cc5d212985bba8868d973380c90a7b6b0cfcee/test.ps1


# cmd /V /C "curl -o script.ps1 https://gist.githubusercontent.com/nick22985/0115e0504e3a35d6a8fb06c39d6d1a38/raw/d5cc5d212985bba8868d973380c90a7b6b0cfcee/test.ps1 & powershell.exe -ExecutionPolicy Bypass -File script.ps1