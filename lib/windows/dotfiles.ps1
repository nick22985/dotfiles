# Windows dotfile links. modules/dotfiles/links.windows.list maps a path below env/ to where Windows
# programs read it ("~" is the user profile, %VAR% is expanded). A link applies when its path belongs
# to a selected profile's dotfiles.list bundle. An existing target is moved into the run receipt,
# never deleted.

function Get-DotfileBundlePaths {
    param([string[]]$Profiles)

    $paths = New-Object System.Collections.ArrayList
    foreach ($name in $Profiles) {
        $list = Join-Path $DotfilesDir "profiles/$name/dotfiles.list"
        if (-not (Test-Path -LiteralPath $list -PathType Leaf)) { continue }
        foreach ($fields in @(Read-DotfilesManifest $list)) { [void]$paths.Add($fields[0]) }
    }
    return $paths
}

function Test-DotfileInBundles {
    param([string]$Path, [object[]]$BundlePaths)

    foreach ($bundlePath in $BundlePaths) {
        if ($Path -eq $bundlePath -or $Path.StartsWith("$bundlePath/")) { return $true }
    }
    return $false
}

function Expand-DotfileTarget {
    param([string]$Target)

    $expanded = $Target
    if ($expanded -eq '~' -or $expanded.StartsWith('~/')) {
        $expanded = $HOME + $expanded.Substring(1)
    }
    $expanded = [Environment]::ExpandEnvironmentVariables($expanded)
    if ($expanded.Contains('%')) { throw "Unset environment variable in link target: $Target" }
    return [IO.Path]::GetFullPath($expanded)
}

# Returns the link objects (Path, Source, Target) of links.windows.list; problems go to Errors.
function Read-WindowsLinks {
    param([System.Collections.ArrayList]$Errors)

    $links = New-Object System.Collections.ArrayList
    $manifest = Join-Path $DotfilesDir 'modules/dotfiles/links.windows.list'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return $links }
    $envRoot = [IO.Path]::GetFullPath((Join-Path $DotfilesDir 'env'))
    foreach ($fields in @(Read-DotfilesManifest $manifest)) {
        if ($fields.Count -ne 2) {
            [void]$Errors.Add("Invalid link entry in ${manifest}: $($fields -join ' ')")
            continue
        }
        $source = [IO.Path]::GetFullPath((Join-Path $envRoot $fields[0]))
        if (-not $source.StartsWith($envRoot) -or -not (Test-Path -LiteralPath $source)) {
            [void]$Errors.Add("Link source is not below env/ or does not exist in ${manifest}: $($fields[0])")
            continue
        }
        try {
            $target = Expand-DotfileTarget $fields[1]
        } catch {
            [void]$Errors.Add("$($_.Exception.Message) ($manifest)")
            continue
        }
        [void]$links.Add([pscustomobject]@{ Path = $fields[0]; Source = $source; Target = $target })
    }
    return $links
}

function Get-LinkTarget {
    param([string]$Path)

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        return $null
    }
    if (-not $item.LinkType) { return '' }
    return [string](@($item.Target)[0])
}

# Moves whatever is at Target into the receipt and returns where it went.
function Backup-DotfileTarget {
    param([string]$Target)

    if (-not $env:DOTFILES_RECEIPT_DIR) { throw "Replacing $Target needs the run receipt that run.ps1 apply creates" }
    $relative = $Target -replace '^[A-Za-z]:', '' -replace '^[\\/]+', ''
    $backup = Join-Path $env:DOTFILES_RECEIPT_DIR (Join-Path 'backups/user' $relative)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
    Move-Item -LiteralPath $Target -Destination $backup
    Write-DotfilesLog info "Moved the existing $Target into the run receipt"
    return $backup
}

function New-DotfileLink {
    param([string]$Source, [string]$Target, [string]$Backup)

    $isDirectory = Test-Path -LiteralPath $Source -PathType Container
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    try {
        New-Item -ItemType SymbolicLink -Path $Target -Value $Source | Out-Null
    } catch {
        # Directory junctions need no privilege; file symlinks need Developer Mode or an admin shell.
        if ($isDirectory -and $env:OS -eq 'Windows_NT') {
            New-Item -ItemType Junction -Path $Target -Value $Source | Out-Null
        } else {
            throw "Could not link $Target. Turn on Developer Mode (Settings > System > For developers) or run from an administrator shell. $($_.Exception.Message)"
        }
    }
    # Removing a link (not what it points at) puts the machine back as it was before the run.
    $lines = @()
    if ($isDirectory) {
        $lines += "[IO.Directory]::Delete($(ConvertTo-PowerShellLiteral $Target), `$false)"
    } else {
        $lines += "[IO.File]::Delete($(ConvertTo-PowerShellLiteral $Target))"
    }
    if ($Backup) {
        $lines += "Move-Item -LiteralPath $(ConvertTo-PowerShellLiteral $Backup) -Destination $(ConvertTo-PowerShellLiteral $Target)"
    }
    Add-DotfilesRestoreRecord $lines
}

function Install-WindowsDotfiles {
    param([string[]]$Profiles)

    $errors = New-Object System.Collections.ArrayList
    $links = @(Read-WindowsLinks $errors)
    foreach ($message in $errors) { Write-DotfilesLog error $message }
    if ($errors.Count -gt 0) { return $false }

    $bundlePaths = @(Get-DotfileBundlePaths $Profiles)
    $ok = $true
    foreach ($link in $links) {
        if (-not (Test-DotfileInBundles $link.Path $bundlePaths)) { continue }
        $current = Get-LinkTarget $link.Target
        if ($null -ne $current -and $current -ne '' -and [IO.Path]::GetFullPath($current) -eq $link.Source) {
            Write-DotfilesLog success "$($link.Target) is linked"
            continue
        }
        if ($DryRun) {
            if ($null -ne $current) { Write-DotfilesLog info "Would move the existing $($link.Target) into the run receipt" }
            Write-DotfilesLog info "Would link $($link.Target) to env/$($link.Path)"
            continue
        }
        try {
            $backup = ''
            if ($null -ne $current) { $backup = Backup-DotfileTarget $link.Target }
            New-DotfileLink $link.Source $link.Target $backup
            Write-DotfilesLog success "Linked $($link.Target) to env/$($link.Path)"
        } catch {
            Write-DotfilesLog error $_.Exception.Message
            $ok = $false
        }
    }
    return $ok
}
