if(!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
	Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`"  `"$($MyInvocation.MyCommand.UnboundArguments)`""
	Exit
}

$USERPROFILE = Get-Content $PROFILE

# Define an array of application names you want to install
$applications = @(
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
	'9NF8H0H7WMLT', # NVIDIA Control Panel
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
     	'GlassWire.GlassWire'
)

# Create a script block for installing an application
$installScript = {
    param (
        [string]$appName
    )
    Write-Host "Installing $appName..."
    winget install -e --id $appName --accept-source-agreements --accept-package-agreements
    Write-Host "$appName installation complete."
}

# Create jobs for installing applications in parallel
$jobs = @()
foreach ($app in $applications) {
    $jobs += Start-Job -ScriptBlock $installScript -ArgumentList $app
}

# Monitor job progress and display messages
$completedJobs = @()
while ($jobs.Count -gt 0) {
    foreach ($job in $jobs) {
        if ($job.State -eq 'Completed') {
            $completedJobs += $job
        }
    }

    # Remove completed jobs from the $jobs array
    $completedJobs | ForEach-Object {
        $jobs.Remove($_)
    }

    # Clear the completedJobs array for the next iteration
    $completedJobs = @()

    # Display progress
    Write-Host "Progress: $($jobs.Count) out of $($applications.Count) remaining."

    # Sleep for a moment to avoid excessive resource usage
    Start-Sleep -Seconds 1
}

# Display job results and remove the completed jobs
$completedJobs | ForEach-Object {
    Receive-Job $_
    Remove-Job $_
}

Write-Host "All installations are complete."

# Refreshes the path variable without needing to restart powershell
$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$content = ':read(\"*a\"))()'
$content1 = "load(io.popen('starship init cmd')$content"
New-Item "$env:LocalAppData\clink\starship.lua" -ItemType File -Value $content1

# checks if powershell profile has starship init
if ($USERPROFILE -contains "Invoke-Expression (&starship init powershell)") {
	Write-host "Starship profile for ps1 already exists"
} else {
	Write-host "Installing Starship profile for ps1"
	Add-Content -Path $PROFILE -Value "`nInvoke-Expression (&starship init powershell)"
}

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


Copy-Item -Path "$Env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Destination "$env:USERPROFILE\windowsTerminal\settings.json" -Force

# install nerd fonts
git clone https://github.com/ryanoasis/nerd-fonts.git "$env:USERPROFILE/Downloads/nerd-fonts"
Invoke-Expression "$env:USERPROFILE/Downloads/nerd-fonts/install.ps1"
wsl --update

