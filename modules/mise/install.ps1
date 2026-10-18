# Installs the selected profiles' tools.list pins with mise, like modules/mise/install on Linux.
. (Join-Path $PSScriptRoot '../../lib/windows/common.ps1')
. (Join-Path $DotfilesDir 'lib/windows/tools.ps1')
Assert-DotfilesRunner

$profiles = @(Get-DotfilesActiveProfiles)
$errors = New-Object System.Collections.ArrayList
$tools = @(Read-ToolLists $profiles $errors)
foreach ($message in $errors) { Write-DotfilesLog error $message }
if ($errors.Count -gt 0) { Exit-DotfilesModule }
if ($tools.Count -eq 0) {
    Write-DotfilesLog error "No tools.list in the selected profiles: $($profiles -join ' ')"
    Exit-DotfilesModule
}

# jdx.mise was installed by the packages module in this run, after this shell's PATH was read.
Update-DotfilesPath
if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    if (-not $DryRun) {
        Write-DotfilesLog error 'mise is required; install the selected package profiles first'
        Exit-DotfilesModule
    }
}

foreach ($entry in $tools) {
    $mode = 'installed'
    if ($entry.Active) { $mode = 'active' }
    if ($DryRun) {
        Write-DotfilesLog info "Would install $($entry.Tool)@$($entry.Version) with mise ($mode)"
        continue
    }
    & mise install "$($entry.Tool)@$($entry.Version)"
    if ($LASTEXITCODE -ne 0) {
        Write-DotfilesLog error "mise could not install $($entry.Tool)@$($entry.Version)"
        continue
    }
    if ($entry.Active) {
        & mise use --global "$($entry.Tool)@$($entry.Version)"
        if ($LASTEXITCODE -ne 0) { Write-DotfilesLog error "mise could not make $($entry.Tool)@$($entry.Version) the global version" }
    }
}

# PowerShell has no mise activate hook here, so the global versions are reached through the shims.
# Only real Windows has a user PATH in the registry.
$shims = Get-MiseShimsDirectory
if ([Environment]::OSVersion.Platform -eq 'Win32NT') {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    if (@($userPath -split ';') -notcontains $shims) {
        if ($DryRun) {
            Write-DotfilesLog info "Would add $shims to the user PATH"
        } else {
            [Environment]::SetEnvironmentVariable('Path', (@(@($userPath -split ';' | Where-Object { $_ -ne '' }) + $shims) -join ';'), 'User')
            Add-DotfilesRestoreRecord @(
                "`$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')"
                "[Environment]::SetEnvironmentVariable('Path', (@(`$userPath -split ';' | Where-Object { `$_ -ne $(ConvertTo-PowerShellLiteral $shims) }) -join ';'), 'User')"
            )
            Write-DotfilesLog success "Added $shims to the user PATH; open a new shell to use it"
        }
    }
}

if ($script:DotfilesErrors -eq 0) { Write-DotfilesLog success 'Pinned mise tools are installed' }
Exit-DotfilesModule
