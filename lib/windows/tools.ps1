# The selected profiles' tools.list pins, installed with mise. Same format as modules/mise/install:
# "tool version active|installed", where active tools also become the global version.

# Returns the tool objects (Tool, Version, Active, Manifest); problems go to Errors.
function Read-ToolLists {
    param([string[]]$Profiles, [System.Collections.ArrayList]$Errors)

    $tools = New-Object System.Collections.ArrayList
    foreach ($name in $Profiles) {
        $manifest = Join-Path $DotfilesDir "profiles/$name/tools.list"
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        foreach ($fields in @(Read-DotfilesManifest $manifest)) {
            if ($fields.Count -ne 3 -or $fields[0] -cnotmatch '^[a-z0-9_-]+$' -or $fields[1] -cnotmatch '^[a-zA-Z0-9._+-]+$' -or $fields[2] -cnotmatch '^(active|installed)$') {
                [void]$Errors.Add("Invalid tool entry in ${manifest}: $($fields -join ' ')")
                continue
            }
            [void]$tools.Add([pscustomobject]@{ Tool = $fields[0]; Version = $fields[1]; Active = ($fields[2] -eq 'active'); Manifest = $manifest })
        }
    }
    return $tools
}

function Test-MiseTool {
    param([string]$Tool, [string]$Version)

    & mise where "$Tool@$Version" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Get-MiseShimsDirectory {
    $dataDir = $env:MISE_DATA_DIR
    if (-not $dataDir) { $dataDir = Join-Path $env:LOCALAPPDATA 'mise' }
    return Join-Path $dataDir 'shims'
}
