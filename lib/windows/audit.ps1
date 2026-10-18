# .\run.ps1 audit: compares the selected profiles with the machine, read-only, like ./run audit.
# Covers what the Windows modules manage: winget packages, dotfile links and mise tools.

# Prints the differences and returns the exit status: with -Check, 1 for differences and 2 when a
# section could not be checked; otherwise 0.
function Invoke-DotfilesAudit {
    param($Selection, [string[]]$Selected, [bool]$Check)

    $profiles = @($Selection.Profiles) + @($Selection.DesktopProfiles)
    $differences = 0
    $incomplete = $false

    if ($Selected -contains 'packages') {
        Write-Host 'Packages:'
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Host '  winget was not found; packages were not checked'
            $incomplete = $true
        } else {
            foreach ($name in $profiles) {
                $errors = New-Object System.Collections.ArrayList
                $entries = @(Resolve-PackageTable (Join-Path $DotfilesDir "profiles/$name/packages.list") $errors)
                foreach ($message in $errors) {
                    Write-Host "  $message"
                    $incomplete = $true
                }
                foreach ($entry in $entries) {
                    if (Test-WingetPackage $entry.Source $entry.Package) { continue }
                    Write-Host "  missing $($entry.Package) ($($entry.Source), profile $name)"
                    $differences++
                }
            }
        }
    }

    if ($Selected -contains 'dotfiles') {
        Write-Host 'Dotfile links:'
        $errors = New-Object System.Collections.ArrayList
        $links = @(Read-WindowsLinks $errors)
        foreach ($message in $errors) {
            Write-Host "  $message"
            $incomplete = $true
        }
        $bundlePaths = @(Get-DotfileBundlePaths $profiles)
        foreach ($link in $links) {
            if (-not (Test-DotfileInBundles $link.Path $bundlePaths)) { continue }
            $current = Get-LinkTarget $link.Target
            if ($null -ne $current -and $current -ne '' -and [IO.Path]::GetFullPath($current) -eq $link.Source) { continue }
            $state = 'missing'
            if ($current -eq '') { $state = 'a file or directory, not a link' }
            elseif ($null -ne $current) { $state = "a link to $current" }
            Write-Host "  $($link.Target) should link to env/$($link.Path) but is $state"
            $differences++
        }
    }

    if ($Selected -contains 'mise') {
        Write-Host 'mise tools:'
        Update-DotfilesPath
        $errors = New-Object System.Collections.ArrayList
        $tools = @(Read-ToolLists $profiles $errors)
        foreach ($message in $errors) {
            Write-Host "  $message"
            $incomplete = $true
        }
        if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
            Write-Host '  mise was not found; tools were not checked'
            $incomplete = $true
        } else {
            foreach ($entry in $tools) {
                if (Test-MiseTool $entry.Tool $entry.Version) { continue }
                Write-Host "  missing $($entry.Tool)@$($entry.Version)"
                $differences++
            }
        }
    }

    Write-Host "Selected state: $($profiles -join ' ')."
    if (-not $Check) { return 0 }
    if ($incomplete) {
        Write-Host 'Audit check incomplete because a required command or declaration was unavailable.'
        return 2
    }
    if ($differences -gt 0) {
        Write-Host 'Audit differences found.'
        return 1
    }
    Write-Host 'No audit differences found.'
    return 0
}
