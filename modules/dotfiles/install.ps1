# Links the selected profiles' Windows dotfiles (modules/dotfiles/links.windows.list).
. (Join-Path $PSScriptRoot '../../lib/windows/common.ps1')
. (Join-Path $DotfilesDir 'lib/windows/dotfiles.ps1')
Assert-DotfilesRunner

if (Install-WindowsDotfiles @(Get-DotfilesActiveProfiles)) { Write-DotfilesLog success 'Dotfiles are linked' }
Exit-DotfilesModule
