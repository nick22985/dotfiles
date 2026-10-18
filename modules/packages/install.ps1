# Installs the windows column of each selected profile's packages.list through winget.
. (Join-Path $PSScriptRoot '../../lib/windows/common.ps1')
. (Join-Path $DotfilesDir 'lib/windows/packages.ps1')
Assert-DotfilesRunner

foreach ($name in @(Get-DotfilesActiveProfiles)) {
    $directory = Join-Path $DotfilesDir "profiles/$name"
    # A profile without a package table (one that only includes others) has nothing to install.
    if (-not (Test-Path -LiteralPath (Join-Path $directory 'packages.list') -PathType Leaf)) { continue }
    Write-DotfilesLog info "Installing package profile: $name"
    [void](Install-PackageList $directory)
}
if ($script:DotfilesErrors -eq 0) { Write-DotfilesLog success 'Profile packages are installed' }
Exit-DotfilesModule
