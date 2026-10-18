# The windows column of a packages.list table (see lib/platforms/common.sh for the format). Sources
# are winget (the default) and msstore, both installed through winget.

$WindowsPackageSources = @('winget', 'msstore')

# Returns the windows entries of a table as objects with Source, Package and Row. Problems are
# collected in the Errors list instead of stopping, so doctor can report every one.
function Resolve-PackageTable {
    param([string]$Path, [System.Collections.ArrayList]$Errors)

    $entries = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $entries }
    $header = $null
    $column = 0
    foreach ($fields in @(Read-DotfilesManifest $Path)) {
        if ($null -eq $header) {
            $header = $fields
            if ($header[0] -cne 'package' -or $header.Count -lt 2) {
                [void]$Errors.Add("Package table $Path must start with a ""package <platform>..."" header")
                return $entries
            }
            for ($index = 1; $index -lt $header.Count; $index++) {
                if ($header[$index] -cnotmatch '^(arch|ubuntu|windows)$' -or @($header | Select-Object -First $index) -ccontains $header[$index]) {
                    [void]$Errors.Add("Invalid platform column in ${Path}: $($header[$index])")
                    return $entries
                }
                if ($header[$index] -ceq 'windows') { $column = $index }
            }
            continue
        }
        if ($fields.Count -ne $header.Count -or $fields[0] -cnotmatch '^[a-z0-9][a-z0-9@._+-]*$') {
            [void]$Errors.Add("Invalid package row in $Path (expected $($header.Count) cells): $($fields -join ' ')")
            continue
        }
        # Every cell is checked, not only this platform's, so a table is valid or invalid everywhere.
        $badCell = @($fields | Select-Object -Skip 1 | Where-Object { $_ -cnotmatch '^(=|-|([a-z]+:)?[A-Za-z0-9][A-Za-z0-9@._+:-]*)$' })
        if ($badCell.Count -gt 0) {
            [void]$Errors.Add("Invalid package cell in ${Path}: $($badCell[0]) (row $($fields[0]))")
            continue
        }
        if ($column -eq 0) { continue }
        $cell = $fields[$column]
        if ($cell -eq '-') { continue }
        if ($cell -eq '=') { $cell = $fields[0] }
        $source = 'winget'
        $package = $cell
        if ($cell.Contains(':')) {
            $source = $cell.Substring(0, $cell.IndexOf(':'))
            $package = $cell.Substring($cell.IndexOf(':') + 1)
        }
        if ($WindowsPackageSources -cnotcontains $source) {
            [void]$Errors.Add("Unknown package source '$source' in $Path (row $($fields[0]))")
            continue
        }
        [void]$entries.Add([pscustomobject]@{ Source = $source; Package = $package; Row = $fields[0] })
    }
    return $entries
}

function Test-WingetPackage {
    param([string]$Source, [string]$Id)

    & winget list --id $Id --exact --source $Source --accept-source-agreements --disable-interactivity *> $null
    return ($LASTEXITCODE -eq 0)
}

# Installs a profile or module directory's packages.list for Windows. Returns $false on any failure.
function Install-PackageList {
    param([string]$Directory)

    $errors = New-Object System.Collections.ArrayList
    $entries = @(Resolve-PackageTable (Join-Path $Directory 'packages.list') $errors)
    foreach ($message in $errors) { Write-DotfilesLog error $message }
    if ($errors.Count -gt 0) { return $false }
    if ($entries.Count -eq 0) { return $true }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-DotfilesLog error 'winget was not found. Install App Installer from the Microsoft Store, then run again.'
        return $false
    }

    $ok = $true
    foreach ($entry in $entries) {
        if (Test-WingetPackage $entry.Source $entry.Package) {
            Write-DotfilesLog success "$($entry.Package) is installed"
            continue
        }
        if ($DryRun) {
            Write-DotfilesLog info "Would install $($entry.Package) from $($entry.Source)"
            continue
        }
        Write-DotfilesLog info "Installing $($entry.Package) from $($entry.Source)"
        & winget install --id $entry.Package --exact --source $entry.Source --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -eq 0) {
            Write-DotfilesLog success "Installed $($entry.Package)"
        } else {
            Write-DotfilesLog error "winget could not install $($entry.Package) (exit code $LASTEXITCODE)"
            $ok = $false
        }
    }
    return $ok
}
