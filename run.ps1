# Windows entry point of the dotfiles installer; ./run is the Linux one. Both read the same
# modules/, profiles/ and hosts/. Run it from PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\run.ps1 plan --host windows

$env:DOTFILES_DIR = $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib/windows/common.ps1')
. (Join-Path $PSScriptRoot 'lib/windows/catalog.ps1')
. (Join-Path $PSScriptRoot 'lib/windows/packages.ps1')
. (Join-Path $PSScriptRoot 'lib/windows/dotfiles.ps1')
. (Join-Path $PSScriptRoot 'lib/windows/tools.ps1')
. (Join-Path $PSScriptRoot 'lib/windows/audit.ps1')

$Platform = 'windows'

function Show-Usage {
    Write-Host @'
Usage:
  .\run.ps1 plan [options]
  .\run.ps1 apply [options]
  .\run.ps1 audit [--profile NAME] [--host NAME] [--skip NAME] [--check]
  .\run.ps1 doctor
  .\run.ps1 self-update
  .\run.ps1 list

Options:
  --profile NAME       Add an installer profile
  --host NAME          Load a saved host selection
  --skip NAME          Exclude a module from the resolved plan
  --script NAME        Run one module after profile filtering
  --dry                Execute modules in dry-run mode
  --check              audit: exit 1 on differences, 2 when something could not be checked

Mutating the machine always requires the explicit apply command.
'@
}

function Show-DotfilesList {
    param($Modules)

    Write-Host 'Profiles available on Windows:'
    foreach ($name in @(Get-ProfileNames)) {
        if ((Test-ProfileSelectable $name) -and (Test-ProfileSupportsPlatform $name $Platform)) {
            Write-Host ('  {0,-16} {1}' -f $name, (@(Get-ProfileValues $name 'description') -join ''))
        }
    }
    Write-Host ''
    Write-Host 'Modules with a Windows version (in run order):'
    foreach ($module in $Modules.Values) {
        if ($module.Platforms -contains $Platform) { Write-Host ('  {0,-16} {1}' -f $module.Name, $module.Description) }
    }
}

# Checks every manifest the Windows runner reads. Returns the problems found.
function Test-DotfilesManifests {
    param($Modules)

    $problems = New-Object System.Collections.ArrayList
    foreach ($module in $Modules.Values) {
        foreach ($dependency in $module.Depends) {
            if (-not $Modules.Contains($dependency)) { [void]$problems.Add("Module '$($module.Name)' has unknown dependency '$dependency'.") }
        }
        if ($module.Platforms -contains $Platform -and -not (Test-Path -LiteralPath $module.Script -PathType Leaf)) {
            [void]$problems.Add("Module install script is missing: $($module.Script)")
        }
    }
    foreach ($name in @(Get-ProfileNames)) {
        foreach ($fields in @(Read-DotfilesManifest (Get-ProfileConfPath $name))) {
            if ($fields[0] -eq 'module' -and -not $Modules.Contains($fields[1])) { [void]$problems.Add("Unregistered module $($fields[1]) in $(Get-ProfileConfPath $name)") }
            if ($fields[0] -eq 'include' -and -not (Test-ProfileExists $fields[1])) { [void]$problems.Add("Unknown profile $($fields[1]) included in $(Get-ProfileConfPath $name)") }
        }
    }
    foreach ($table in (Get-ChildItem -Path (Join-Path $DotfilesDir '*/*/packages.list'))) {
        [void](Resolve-PackageTable $table.FullName $problems)
    }
    [void](Read-WindowsLinks $problems)
    foreach ($hostFile in (Get-ChildItem -Path (Join-Path $DotfilesDir 'hosts/*.conf'))) {
        $platformLine = @(Read-DotfilesManifest $hostFile.FullName | Where-Object { $_[0] -eq 'platform' })
        if ($platformLine.Count -eq 0 -or $platformLine[0][1] -ne $Platform) { continue }
        try {
            $selection = New-DotfilesSelection
            Import-SelectionHost $selection $hostFile.BaseName
            Resolve-DotfilesSelection $selection
            [void](Select-DotfilesModules $selection $Modules $Platform '')
        } catch {
            [void]$problems.Add("Host preset $($hostFile.BaseName): $($_.Exception.Message)")
        }
    }
    return $problems
}

function Write-DotfilesPlan {
    param($Selection, [string]$HostName, [string[]]$Selected, $Modules)

    $lines = @("Platform: $Platform")
    if ($HostName) { $lines += "Host preset: $HostName" }
    $lines += "Profiles: $($Selection.Profiles -join ' ')"
    if ($Selection.Skips.Count -gt 0) { $lines += "Skipped: $($Selection.Skips -join ' ')" }
    $lines += 'Modules:'
    foreach ($name in $Selected) {
        $marker = 'user'
        if ($Modules[$name].Root -eq 'yes') { $marker = 'root' }
        $lines += ('  {0,-20} {1,-4} {2,-6} {3}' -f $name, $marker, $Modules[$name].Risk, $Modules[$name].Description)
    }
    return $lines
}

function Invoke-SelfUpdate {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required for self-update.' }
    if (& git -C $DotfilesDir status --porcelain --untracked-files=normal) { throw 'Refusing to update a dirty dotfiles worktree.' }
    $branch = & git -C $DotfilesDir branch --show-current
    if (-not $branch) { throw 'Refusing to update a detached HEAD.' }
    & git -C $DotfilesDir pull --ff-only origin $branch | Out-Host
    if ($LASTEXITCODE -ne 0) { exit 1 }
    & git -C $DotfilesDir submodule update --init --recursive | Out-Host
    if ($LASTEXITCODE -ne 0) { exit 1 }
    Write-Host "Updated dotfiles on $branch. Run .\run.ps1 plan before applying."
}

function Invoke-DotfilesRunner {
    param([string[]]$Arguments)

    if ($Arguments.Count -eq 0 -or $Arguments[0] -in @('-h', '--help')) {
        Show-Usage
        return 0
    }
    if ($env:OS -ne 'Windows_NT') {
        Write-Host 'run.ps1 is the Windows installer; use ./run on Linux.' -ForegroundColor Red
        return 2
    }
    $action = $Arguments[0]
    $rest = @($Arguments | Select-Object -Skip 1)
    $modules = Get-DotfilesModules

    switch ($action) {
        'list' {
            Show-DotfilesList $modules
            return 0
        }
        'doctor' {
            $problems = @(Test-DotfilesManifests $modules)
            foreach ($problem in $problems) { Write-Host $problem -ForegroundColor Red }
            if ($problems.Count -gt 0) { return 1 }
            Write-Host "Installer manifests and modules are valid for $Platform."
            return 0
        }
        'self-update' {
            if ($rest.Count -gt 0) { throw 'self-update does not accept options.' }
            Invoke-SelfUpdate
            return 0
        }
        { $_ -in @('plan', 'apply', 'audit') } { }
        default {
            Write-Host "Unknown command: $action" -ForegroundColor Red
            Show-Usage
            return 2
        }
    }

    $selection = New-DotfilesSelection
    $hostName = ''
    $only = ''
    $check = $false
    for ($index = 0; $index -lt $rest.Count; $index++) {
        $option = $rest[$index]
        $value = $null
        if ($option -match '^(--[a-z]+)=(.*)$') {
            $option = $Matches[1]
            $value = $Matches[2]
        }
        if ($option -in @('--profile', '--host', '--skip', '--script', '--desktop') -and $null -eq $value) {
            $index++
            if ($index -ge $rest.Count) { throw "$option requires a value" }
            $value = $rest[$index]
        }
        if ($action -eq 'audit' -and $option -notin @('--profile', '--host', '--skip', '--desktop', '--check')) { throw "audit does not accept $option" }
        switch ($option) {
            '--check' {
                if ($action -ne 'audit') { throw '--check is an audit option' }
                $check = $true
            }
            '--dry' { $env:DRY_RUN = '1'; $script:DryRun = $true }
            '--profile' { Add-SelectionProfile $selection $value }
            '--desktop' { Set-SelectionDesktop $selection $value }
            '--host' { $hostName = $value; Import-SelectionHost $selection $value }
            '--skip' { [void]$selection.Skips.Add($value) }
            '--script' { $only = $value }
            default {
                if ($option.StartsWith('--')) { throw "Unknown option: $option" }
                if ($only) { throw "Only one module may be selected: $only, $option" }
                $only = $option
            }
        }
    }
    if (-not $selection.Mode) {
        $defaultFile = Join-Path $DotfilesDir 'hosts/default.conf'
        $defaultPlatform = @(Read-DotfilesManifest $defaultFile | Where-Object { $_[0] -eq 'platform' })
        # hosts/default.conf describes the Linux workstation; Windows defaults to core unless it says windows.
        if ($defaultPlatform.Count -gt 0 -and $defaultPlatform[0][1] -eq $Platform) {
            Import-SelectionManifest $selection $defaultFile
        }
    }
    if ($selection.Platform -and $selection.Platform -ne $Platform) {
        throw "The selection is for $($selection.Platform), but this machine is $Platform."
    }

    Resolve-DotfilesSelection $selection
    foreach ($name in @($selection.Profiles) + @($selection.DesktopProfiles)) {
        if (-not (Test-ProfileSupportsPlatform $name $Platform)) {
            throw "Profile '$name' is not available on $Platform (platforms: $(@(Get-ProfileValues $name 'platforms') -join ''))"
        }
    }
    $selected = @(Select-DotfilesModules $selection $modules $Platform $only)
    if ($selected.Count -eq 0) { throw 'The selected profiles resolve to no Windows modules.' }
    foreach ($name in $selected) {
        if (-not (Test-Path -LiteralPath $modules[$name].Script -PathType Leaf)) { throw "Selected module is missing: $($modules[$name].Script)" }
    }

    if ($action -eq 'audit') { return (Invoke-DotfilesAudit $selection $selected $check) }

    $plan = @(Write-DotfilesPlan $selection $hostName $selected $modules)
    $plan | ForEach-Object { Write-Host $_ }
    if ($action -eq 'plan') { return 0 }
    Write-Host ''

    $stateRoot = Join-Path $env:LOCALAPPDATA 'dotfiles'
    New-Item -ItemType Directory -Force -Path (Join-Path $stateRoot 'runs') | Out-Null
    try {
        $lock = [IO.File]::Open((Join-Path $stateRoot 'apply.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    } catch {
        throw 'Another dotfiles apply is already running.'
    }
    try {
        $runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), $PID
        $receipt = Join-Path $stateRoot "runs/$runId"
        New-Item -ItemType Directory -Force -Path (Join-Path $receipt 'backups/user') | Out-Null
        Set-Content -LiteralPath (Join-Path $receipt 'plan.txt') -Value $plan -Encoding UTF8
        $commit = & git -C $DotfilesDir rev-parse HEAD 2>$null
        if (-not $commit) { $commit = 'unknown' }
        Set-Content -LiteralPath (Join-Path $receipt 'commit') -Value $commit -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $receipt 'modules.tsv') -Value "module`tstatus`tduration_seconds" -Encoding UTF8
        # Modules add one record per change to restore.d/user/; the script undoes them newest first.
        $restoreScript = @(
            '$ErrorActionPreference = ''Stop'''
            '$records = Join-Path $PSScriptRoot ''restore.d/user'''
            'if (-not (Test-Path -LiteralPath $records)) { exit 0 }'
            'foreach ($record in @(Get-ChildItem -LiteralPath $records -Filter ''*.ps1'' | Sort-Object Name -Descending)) { . $record.FullName }'
        )
        Set-Content -LiteralPath (Join-Path $receipt 'restore-user.ps1') -Value $restoreScript -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $stateRoot 'latest') -Value $receipt -Encoding UTF8

        $env:DOTFILES_PLATFORM = $Platform
        $env:DOTFILES_RECEIPT_DIR = $receipt
        $env:DOTFILES_ACTIVE_PROFILES = $selection.Profiles -join ' '
        $env:DOTFILES_DESKTOP_PROFILES = $selection.DesktopProfiles -join ' '
        $env:DOTFILES_RUNNER_ACTIVE = '1'
        $shell = (Get-Process -Id $PID).Path

        $results = @{}
        $failed = @()
        foreach ($name in $selected) {
            $blocked = @($modules[$name].Depends | Where-Object { $results.ContainsKey($_) -and $results[$_] -ne 'success' })
            if ($blocked.Count -gt 0) {
                Write-DotfilesLog error "Skipping module $name because dependency $($blocked[0]) $($results[$blocked[0]])"
                $results[$name] = 'skipped'
                $failed += $name
                Add-Content -LiteralPath (Join-Path $receipt 'modules.tsv') -Value "$name`tskipped`t0" -Encoding UTF8
                continue
            }
            Write-Host "Running module: $name"
            $started = Get-Date
            & $shell -NoProfile -ExecutionPolicy Bypass -File $modules[$name].Script | Out-Host
            $status = $LASTEXITCODE
            $duration = [int]((Get-Date) - $started).TotalSeconds
            if ($status -eq 0) {
                $results[$name] = 'success'
            } else {
                $results[$name] = 'failed'
                $failed += $name
                Write-DotfilesLog error "Module $name exited with status $status"
            }
            Add-Content -LiteralPath (Join-Path $receipt 'modules.tsv') -Value "$name`t$($results[$name])`t$duration" -Encoding UTF8
            Write-Host ''
        }

        if ($failed.Count -gt 0) {
            Write-Host "Failed modules: $($failed -join ' ')"
            Set-Content -LiteralPath (Join-Path $receipt 'exit-status') -Value '1' -Encoding UTF8
            Write-Host "Run receipt: $receipt"
            return 1
        }
        if ($DryRun) {
            Write-Host "Dry run completed for $($selected.Count) module(s)."
        } else {
            Write-Host "Applied $($selected.Count) module(s) successfully."
        }
        Set-Content -LiteralPath (Join-Path $receipt 'exit-status') -Value '0' -Encoding UTF8
        Write-Host "Run receipt: $receipt"
        return 0
    } finally {
        $lock.Dispose()
    }
}

try {
    exit (Invoke-DotfilesRunner $args)
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 2
}
