if(!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
	Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList "-noexit", "-ExecutionPolicy Bypass", "-File `"$($MyInvocation.MyCommand.Path)`"  `"$($MyInvocation.MyCommand.UnboundArguments)`""
	Exit
}

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned

$USERPROFILE = Get-Content $PROFILE

function wingetApplication {
	param(
		$applicationId
	)
	$applicationId | ForEach-Object {
		Write-host "Installing $_"
		$application = winget install --id=$_ -e --force --accept-source-agreements --accept-package-agreements
		Write-Host $application
	}
}

$packages = [string[]](
	'Valve.Steam',
	'Obsidian.Obsidian',
	'OBSProject.OBSStudio',
	'Notepad++.Notepad++',
	'OpenJS.NodeJS',
	'Discord.Discord',
	'Microsoft.WindowsTerminal',
	'PuTTY.PuTTY',
	'AgileBits.1Password',
	'AgileBits.1Password.CLI',
	'Microsoft.VisualStudioCode',
	'Microsoft.VisualStudio.2022.Community.Preview',
	'VB-Audio.Voicemeeter.Potato',
	'Elgato.StreamDeck',
	'Microsoft.Teams',
	'Oracle.JavaRuntimeEnvironment',
	'Mojang.MinecraftLauncher',
	'JannisX11.Blockbench',
	'Kitware.CMake',
	'BurntSushi.ripgrep.MSVC',
	'Microsoft.Office',
	'GnuWin32.Make',
	'Neovim.Neovim.Nightly',
	'NordSecurity.NordVPN',
	'Adobe.Acrobat.Reader.64-bit',
	'SlackTechnologies.Slack',
	'Corsair.iCUE.4',
	'Nota.Gyazo',
	'Flameshot.Flameshot',
	'MongoDB.Server',
	'MongoDB.Compass.Community',
	'MongoDB.Shell',
	'MongoDB.DatabaseTools',
	'Oracle.MySQL',
	'junegunn.fzf',
	'GOG.Galaxy',
	'wez.wezterm',
	'Starship.Starship',
	'chrisant996.Clink',
	'Python.Python.3.11',
	'WinSCP.WinSCP',
	'WinDirStat.WinDirStat',
	'GnuPG.Gpg4win',
	'GnuPG.GnuPG',
	'Hex-Rays.IDA.Free',
	'Rustlang.Rustup',
	'REALiX.HWiNFO',
	'Docker.DockerDesktop',
	'DBBrowserForSQLite.DBBrowserForSQLite',
	'Cloudflare.cloudflared',
	'OpenVPNTechnologies.OpenVPN',
	'VideoLAN.VLC',
	'KDE.Kdenlive',
	'GIMP.GIMP',
	'EaseUS.PartitionMaster',
	'EaseUS.DataRecovery',
	'EaseUS.TodoBackup',
	'EpicGames.EpicGamesLauncher',
	'Google.Chrome',
	'Mozilla.Firefox',
	'BlenderFoundation.Blender',
	'WiresharkFoundation.Wireshark',
	'RARLab.WinRAR',
	'Nvidia.GeForceExperience',
	'Spotify.Spotify',
	'CoreyButler.NVMforWindows',
	'Postman.Postman',
	'Ubisoft.Connect',
	'Microsoft.WindowsSDK',
	'WinFsp.WinFsp',
	'Unity.UnityHub',
	'ActivityWatch.ActivityWatch',
 	'gstreamerproject.gstreamer',
  	'gnupg.Gpg4win',
   	'Codeblocks.Codeblocks', #gcc
    	'Insecure.Npcap',
     	'GlassWire.GlassWire',
      	'Samsung.SamsungMagician',
       'JetBrains.IntelliJIDEA.Community',
       'MongoDB.Compass.Full',
       'Malwarebytes.Malwarebytes',
       'JetBrains.PyCharm.Community',
       'JetBrains.IntelliJIDEA.Community',
       'LabyMediaGmbH.LabyModLauncher',
       'wez.wezterm'
       
)

wingetApplication -applicationId $packages

# Refreshes the path variable without needing to restart powershell
$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$content = ':read(\"*a\"))()'
$content1 = "load(io.popen('starship init cmd')$content"
New-Item "$env:LocalAppData\clink\starship.lua" -ItemType File -Value $content1

Install-Module -Name Terminal-Icons -Repository PSGallery
if ($USERPROFILE -contains "Import-Module -Name Terminal-Icons") {
} else {
	Add-Content -Path $PROFILE -Value "Import-Module -Name Terminal-Icons"
}


if ($USERPROFILE -contains "Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete") {
} else {
	Add-Content -Path $PROFILE -Value "Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete"
}
if ($USERPROFILE -contains "Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward") {
} else {
	Add-Content -Path $PROFILE -Value "Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward"
}

if ($USERPROFILE -contains "Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward") {
} else {
	Add-Content -Path $PROFILE -Value "Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward"
}

# checks if powershell profile has starship init
if ($USERPROFILE -contains "Invoke-Expression (&starship init powershell)") {
	Write-host "Starship profile for ps1 already exists"
} else {
	Write-host "Installing Starship profile for ps1"
	Add-Content -Path $PROFILE -Value "`nInvoke-Expression (&starship init powershell)"
}

# install nerd fonts
git clone --filter=blob:none --sparse git@github.com:ryanoasis/nerd-fonts "$env:USERPROFILE/Downloads/nerd-fonts"

Invoke-Expression "$env:USERPROFILE/Downloads/nerd-fonts/install.ps1"

# add ssh keys
$KEY_URL = "https://github.com/nick22985.keys"
$AUTHORIZED_KEYS_FILE = "$HOME\.ssh\authorized_keys"
$response = Invoke-WebRequest -Uri $KEY_URL
$keys = $response.Content -split "`n"
foreach ($key in $keys) {
	$key = $key.Trim()
	if (-not [string]::IsNullOrWhiteSpace($key)) {
		$existingKeys = Get-Content -Path $AUTHORIZED_KEYS_FILE
		$keyExists = $existingKeys -contains $key
		if ($keyExists) {
			Write-Host "Key already exists in $AUTHORIZED_KEYS_FILE"
		}
		else {
			Add-Content -Path $AUTHORIZED_KEYS_FILE -Value $key
			Write-Host "Key added to $AUTHORIZED_KEYS_FILE"
		}
	}
}

# Set Environment Variables
[Environment]::SetEnvironmentVariable("MXDG_CONFIG_HOME", "$env:USERPROFILE\.config", "User")
[Environment]::SetEnvironmentVariable("HOME", "$env:USERPROFILE", "User")

# Set windows to dark mode
New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name SystemUsesLightTheme -Value 0 -Type Dword -Force; New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name AppsUseLightTheme -Value 0 -Type Dword -Force

Copy-Item -Path "$Env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Destination "$env:USERPROFILE\windowsTerminal\settings.json" -Force

# Install the OpenSSH Client
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Install the OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

Start-Service sshd

Set-Service -Name sshd -StartupType 'Automatic'

# Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
}

# By default the ssh-agent service is disabled. Configure it to start automatically.
# Make sure you're running as an Administrator.
Get-Service ssh-agent | Set-Service -StartupType Automatic

# Start the service
Start-Service ssh-agent

# This should return a status of Running
Get-Service ssh-agent


wsl --update
wsl --set-default-version 2

# https://www.memurai.com/get-memurai
# https://redis.com/redis-enterprise/redis-insight/
# openssh (set private key file automatically)
