# Shared by run.ps1 and the modules' install.ps1 scripts on Windows. Written for Windows PowerShell
# 5.1 as well as PowerShell 7, so it avoids syntax newer than 5.1 and non-ASCII text.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $env:DOTFILES_DIR) {
    $env:DOTFILES_DIR = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
}
$DotfilesDir = $env:DOTFILES_DIR
$DryRun = ($env:DRY_RUN -eq '1')
$script:DotfilesErrors = 0

function Write-DotfilesLog {
    param([string]$Level, [string]$Message)

    $prefix = ''
    if ($DryRun) { $prefix = '[DRY_RUN] ' }
    switch ($Level) {
        'info' { Write-Host "$prefix-> $Message" }
        'success' { Write-Host "$prefix" -NoNewline; Write-Host "ok $Message" -ForegroundColor Green }
        'warn' { Write-Host "$prefix" -NoNewline; Write-Host "!! $Message" -ForegroundColor Yellow }
        'error' {
            $script:DotfilesErrors++
            Write-Host "$prefix" -NoNewline
            Write-Host "xx $Message" -ForegroundColor Red
        }
        default { Write-Host "$prefix$Message" }
    }
}

# Non-empty, non-comment lines of a manifest, each split into its whitespace-separated fields.
function Read-DotfilesManifest {
    param([string]$Path)

    $rows = New-Object System.Collections.ArrayList
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        [void]$rows.Add([string[]]($trimmed -split '\s+'))
    }
    return $rows
}

# The module scripts are private: they need the environment run.ps1 sets up.
function Assert-DotfilesRunner {
    if ($env:DOTFILES_RUNNER_ACTIVE -ne '1') {
        Write-Host 'Module scripts are run by run.ps1, for example: .\run.ps1 apply --dry' -ForegroundColor Red
        exit 2
    }
}

function Get-DotfilesActiveProfiles {
    $names = @()
    foreach ($value in @($env:DOTFILES_ACTIVE_PROFILES, $env:DOTFILES_DESKTOP_PROFILES)) {
        if ($value) { $names += @($value -split '\s+' | Where-Object { $_ -ne '' }) }
    }
    return $names
}

# Records the PowerShell lines that undo one change. restore-user.ps1 in the run receipt runs the
# records newest first, so a path changed twice in one run is put back as it was before the run.
function Add-DotfilesRestoreRecord {
    param([string[]]$Lines)

    if (-not $env:DOTFILES_RECEIPT_DIR) { return }
    $directory = Join-Path $env:DOTFILES_RECEIPT_DIR 'restore.d/user'
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $count = @(Get-ChildItem -LiteralPath $directory -Filter '*.ps1').Count
    Set-Content -LiteralPath (Join-Path $directory ('{0:D6}.ps1' -f $count)) -Value $Lines -Encoding UTF8
}

# Adds the machine and user PATH from the registry, so programs winget installed earlier in this run
# are found without opening a new shell.
function Update-DotfilesPath {
    $entries = @($env:PATH -split [IO.Path]::PathSeparator)
    foreach ($scope in @('Machine', 'User')) {
        $value = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ($value) { $entries += @($value -split [IO.Path]::PathSeparator) }
    }
    $env:PATH = (@($entries | Where-Object { $_ -ne '' } | Select-Object -Unique) -join [IO.Path]::PathSeparator)
}

function ConvertTo-PowerShellLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

# Ends a module script: a non-zero exit tells run.ps1 the module failed.
function Exit-DotfilesModule {
    if ($script:DotfilesErrors -gt 0) { exit 1 }
    exit 0
}
