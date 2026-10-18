# The Windows side of modules/, profiles/ and hosts/, read the same way lib/modules.sh and
# lib/profiles.sh read them.

function Get-DotfilesModules {
    $orderFile = Join-Path $DotfilesDir 'modules/order.list'
    $modules = [ordered]@{}
    foreach ($fields in @(Read-DotfilesManifest $orderFile)) {
        $name = $fields[0]
        if ($fields.Count -ne 1 -or $name -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $modules.Contains($name)) {
            throw "Invalid or duplicate entry in ${orderFile}: $($fields -join ' ')"
        }
        $conf = Join-Path $DotfilesDir "modules/$name/module.conf"
        if (-not (Test-Path -LiteralPath $conf -PathType Leaf)) { throw "Module config not found: $conf" }
        $module = [pscustomobject]@{
            Name = $name; Description = ''; Root = ''; Depends = @(); Platforms = @(); Risk = ''
            Script = Join-Path $DotfilesDir "modules/$name/install.ps1"
        }
        foreach ($line in @(Read-DotfilesManifest $conf)) {
            $values = @($line | Select-Object -Skip 1)
            switch ($line[0]) {
                'description' { $module.Description = $values -join ' ' }
                'root' { $module.Root = $values -join ' ' }
                'depends' { $module.Depends = $values }
                'platforms' { $module.Platforms = $values }
                'risk' { $module.Risk = $values -join ' ' }
                default { throw "Unknown key '$($line[0])' in $conf" }
            }
        }
        if ($module.Root -notmatch '^(yes|no)$' -or $module.Risk -notmatch '^(normal|high)$' -or $module.Platforms.Count -eq 0 -or $module.Description -eq '') {
            throw "Invalid module config ${conf}: needs description, root yes|no, platforms and risk normal|high"
        }
        $modules[$name] = $module
    }
    return $modules
}

function Get-ProfileConfPath {
    param([string]$Name)
    return Join-Path $DotfilesDir "profiles/$Name/profile.conf"
}

function Test-ProfileExists {
    param([string]$Name)
    return ($Name -cmatch '^[a-z0-9][a-z0-9-]*$' -and (Test-Path -LiteralPath (Get-ProfileConfPath $Name) -PathType Leaf))
}

function Get-ProfileValues {
    param([string]$Name, [string]$Key)

    $values = @()
    foreach ($fields in @(Read-DotfilesManifest (Get-ProfileConfPath $Name))) {
        if ($fields[0] -eq $Key) { $values += (@($fields | Select-Object -Skip 1) -join ' ') }
    }
    return $values
}

function Get-ProfileNames {
    $names = @()
    foreach ($dir in (Get-ChildItem -LiteralPath (Join-Path $DotfilesDir 'profiles') -Directory | Sort-Object Name)) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName 'profile.conf') -PathType Leaf) { $names += $dir.Name }
    }
    return $names
}

# A profile without a platforms line is for every platform.
function Test-ProfileSupportsPlatform {
    param([string]$Name, [string]$Platform)

    $platforms = @(Get-ProfileValues $Name 'platforms')
    if ($platforms.Count -eq 0) { return $true }
    return (@($platforms[0] -split '\s+') -contains $Platform)
}

function Test-ProfileSelectable {
    param([string]$Name)
    return ((Test-ProfileExists $Name) -and @(Get-ProfileValues $Name 'desktop').Count -eq 0)
}

function New-DotfilesSelection {
    return [pscustomobject]@{
        Mode = $false; Platform = ''; Desktop = 'hyprland'; DesktopExplicit = $false
        Requested = New-Object System.Collections.ArrayList
        Skips = New-Object System.Collections.ArrayList
        LoadedHosts = @{}
        Profiles = New-Object System.Collections.ArrayList
        DesktopProfiles = New-Object System.Collections.ArrayList
        Runs = New-Object System.Collections.ArrayList
        Expanded = @{}
    }
}

function Add-SelectionProfile {
    param($Selection, [string]$Name)

    if (-not (Test-ProfileSelectable $Name)) { throw "Unknown profile: $Name. See .\run.ps1 list." }
    $Selection.Mode = $true
    if ($Selection.Requested -notcontains $Name) { [void]$Selection.Requested.Add($Name) }
}

function Set-SelectionDesktop {
    param($Selection, [string]$Desktop)

    $known = @('both')
    foreach ($name in @(Get-ProfileNames)) { $known += @(Get-ProfileValues $name 'desktop') }
    if ($known -notcontains $Desktop) { throw "Unknown desktop: $Desktop" }
    $Selection.Desktop = $Desktop
    $Selection.DesktopExplicit = $true
    $Selection.Mode = $true
}

# Host presets and hosts/default.conf: profile, desktop, skip, platform and include lines.
function Import-SelectionManifest {
    param($Selection, [string]$Path)

    foreach ($fields in @(Read-DotfilesManifest $Path)) {
        if ($fields.Count -ne 2) { throw "Invalid entry in ${Path}: $($fields -join ' ')" }
        switch ($fields[0]) {
            'profile' { Add-SelectionProfile $Selection $fields[1] }
            'desktop' { Set-SelectionDesktop $Selection $fields[1] }
            'skip' { [void]$Selection.Skips.Add($fields[1]) }
            'platform' { $Selection.Platform = $fields[1] }
            'include' { Import-SelectionHost $Selection $fields[1] }
            default { throw "Unknown key '$($fields[0])' in $Path" }
        }
    }
}

function Import-SelectionHost {
    param($Selection, [string]$HostName)

    if ($HostName -notmatch '^[A-Za-z0-9_-]+$') { throw "Invalid host preset name: $HostName" }
    $path = Join-Path $DotfilesDir "hosts/$HostName.conf"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Host preset not found: $path" }
    # Presets can include each other; each loads once.
    if ($Selection.LoadedHosts.ContainsKey($HostName)) { return }
    $Selection.LoadedHosts[$HostName] = $true
    $Selection.Mode = $true
    Import-SelectionManifest $Selection $path
}

# Adds a profile's included profiles, its modules, then the profile itself; each is expanded once.
function Expand-SelectionProfile {
    param($Selection, [string]$Name)

    if ($Selection.Expanded.ContainsKey($Name)) { return }
    $Selection.Expanded[$Name] = $true
    if (-not (Test-ProfileExists $Name)) { throw "Profile not found: $(Get-ProfileConfPath $Name)" }
    foreach ($fields in @(Read-DotfilesManifest (Get-ProfileConfPath $Name))) {
        switch ($fields[0]) {
            'include' { Expand-SelectionProfile $Selection $fields[1] }
            'module' { if ($Selection.Runs -notcontains $fields[1]) { [void]$Selection.Runs.Add($fields[1]) } }
            { $_ -in @('description', 'desktop', 'platforms') } { }
            default { throw "Unknown key '$($fields[0])' in $(Get-ProfileConfPath $Name)" }
        }
    }
    if ($Selection.Profiles -notcontains $Name) { [void]$Selection.Profiles.Add($Name) }
}

function Resolve-DotfilesSelection {
    param($Selection)

    Expand-SelectionProfile $Selection 'core'
    foreach ($name in $Selection.Requested) { Expand-SelectionProfile $Selection $name }
    if ($Selection.DesktopExplicit) { Expand-SelectionProfile $Selection 'desktop' }
    if ($Selection.Profiles -contains 'desktop') {
        foreach ($name in @(Get-ProfileNames)) {
            $variant = @(Get-ProfileValues $name 'desktop')
            if ($variant.Count -eq 0) { continue }
            if ($Selection.Desktop -ne 'both' -and $Selection.Desktop -ne $variant[0]) { continue }
            [void]$Selection.DesktopProfiles.Add($name)
            foreach ($module in @(Get-ProfileValues $name 'module')) {
                if ($Selection.Runs -notcontains $module) { [void]$Selection.Runs.Add($module) }
            }
        }
    }
}

# The modules to run, in order: every profile module this platform has, plus their dependencies.
function Select-DotfilesModules {
    param($Selection, $Modules, [string]$Platform, [string]$Only)

    $state = @{}
    $visit = {
        param([string]$Name)
        if ($state[$Name] -eq 'selected') { return }
        if ($state[$Name] -eq 'visiting') { throw "Dependency cycle contains module: $Name" }
        if ($Selection.Skips -contains $Name) { throw "Required module '$Name' was excluded with --skip." }
        if (-not $Modules.Contains($Name)) { throw "Unknown module: $Name" }
        if ($Modules[$Name].Platforms -notcontains $Platform) { throw "Module '$Name' does not support platform '$Platform'." }
        $state[$Name] = 'visiting'
        foreach ($dependency in $Modules[$Name].Depends) { & $visit $dependency }
        $state[$Name] = 'selected'
    }

    foreach ($skip in $Selection.Skips) {
        if (-not $Modules.Contains($skip)) { throw "Unknown module in --skip: $skip" }
    }
    if ($Only) {
        if (-not $Modules.Contains($Only) -or $Selection.Skips -contains $Only -or $Selection.Runs -notcontains $Only) {
            throw "Module '$Only' is unknown, skipped, or outside the selected profiles."
        }
        & $visit $Only
    } else {
        foreach ($name in $Modules.Keys) {
            if ($Selection.Runs -notcontains $name -or $Selection.Skips -contains $name) { continue }
            # Profiles list every module they use; the ones this platform has no version of are left out.
            if ($Modules[$name].Platforms -notcontains $Platform) { continue }
            & $visit $name
        }
    }
    $selected = @()
    foreach ($name in $Modules.Keys) {
        if ($state[$name] -eq 'selected') { $selected += $name }
    }
    return $selected
}
