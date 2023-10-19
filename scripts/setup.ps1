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
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "Git is installed."
} else {   
	Write-Host "Installing GIT."
	winget install -e --id=Git.Git --force --accept-source-agreements --accept-package-agreements
}
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

$sshDirectory = [System.IO.Path]::Combine($env:USERPROFILE, ".ssh")
$knownHostsFile = [System.IO.Path]::Combine($sshDirectory, "known_hosts")

if (-not (Test-Path -Path $sshDirectory -PathType Container)) {
    New-Item -Path $sshDirectory -ItemType Directory
}
# Define the new host keys (add your host keys here)
$newHostKeys = @"
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
"@

# Check if the known_hosts file exists
if (Test-Path -Path $knownHostsFile -PathType Leaf) {
    # Read the existing known_hosts file
    $existingHostKeys = Get-Content -Path $knownHostsFile
    $existingKeysArray = $existingHostKeys -split "`n"

    # Check if any of the new host keys are already in the known_hosts file
    $keysToAdd = @()
    foreach ($newKey in ($newHostKeys -split "`n")) {
        if (-not ($existingKeysArray -contains $newKey)) {
            $keysToAdd += $newKey
        }
    }

    if ($keysToAdd.Count -gt 0) {
        # Append the new keys to the known_hosts file
        $keysToAdd | Out-File -FilePath $knownHostsFile -Append
        Write-Host "Added new host keys to $knownHostsFile."
    } else {
        Write-Host "No new host keys were added."
    }
} else {
    # Create the known_hosts file and add the new keys
    $newHostKeys | Out-File -FilePath $knownHostsFile -Force
    Write-Host "Created $knownHostsFile and added host keys."
}

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
