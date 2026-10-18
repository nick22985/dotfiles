# Checks Git, the SSH keys and the GPG key env/.gitconfig signs with, like modules/git/install on
# Linux. Git for Windows bundles its own gpg with a separate keyring, so this also points Git at
# Gpg4win's gpg through ~/.gitconfig.local, which env/.gitconfig includes last.
. (Join-Path $PSScriptRoot '../../lib/windows/common.ps1')
Assert-DotfilesRunner

# Git.Git and GnuPG.Gpg4win were installed by the packages module in this run.
Update-DotfilesPath
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    if (-not $DryRun) { Write-DotfilesLog error 'Git is unavailable; install the core package profile first' }
    Exit-DotfilesModule
}

$sshKeys = @('id_rsa', 'id_ed25519', 'id_ecdsa') | Where-Object { Test-Path -LiteralPath (Join-Path $HOME ".ssh/$_") -PathType Leaf }
if (@($sshKeys).Count -gt 0) {
    Write-DotfilesLog success "Found SSH key: $(@($sshKeys) -join ', ')"
} else {
    Write-DotfilesLog warn "No SSH keys found in $(Join-Path $HOME '.ssh'); generate one with: ssh-keygen -t ed25519"
}

$gpg = ''
foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if ($root -and (Test-Path -LiteralPath (Join-Path $root 'GnuPG/bin/gpg.exe') -PathType Leaf)) {
        $gpg = Join-Path $root 'GnuPG/bin/gpg.exe'
        break
    }
}
if (-not $gpg) {
    $command = Get-Command gpg -ErrorAction SilentlyContinue
    if ($command) { $gpg = $command.Source }
}
if (-not $gpg) {
    if ($DryRun) {
        Write-DotfilesLog info 'Would point Git at Gpg4win once the packages module has installed it'
    } else {
        Write-DotfilesLog warn 'GnuPG was not found; commits fail until Gpg4win is installed because env/.gitconfig signs them'
    }
    Exit-DotfilesModule
}

$signingKey = & git config --file (Join-Path $DotfilesDir 'env/.gitconfig') user.signingkey
& $gpg --list-secret-keys $signingKey *> $null
if ($LASTEXITCODE -eq 0) {
    Write-DotfilesLog success "Found the GPG signing key $signingKey"
} else {
    Write-DotfilesLog warn "GPG signing key $signingKey is missing; import it with: gpg --import <secret key file>. Commits fail until then."
}

$localConfig = Join-Path $HOME '.gitconfig.local'
$current = ''
if (Test-Path -LiteralPath $localConfig -PathType Leaf) { $current = [string](& git config --file $localConfig gpg.program) }
if ($current -eq $gpg) {
    Write-DotfilesLog success "Git uses $gpg"
} elseif ($DryRun) {
    Write-DotfilesLog info "Would set gpg.program to $gpg in $localConfig"
} else {
    $existed = Test-Path -LiteralPath $localConfig -PathType Leaf
    & git config --file $localConfig gpg.program $gpg
    if ($LASTEXITCODE -ne 0) {
        Write-DotfilesLog error "Could not set gpg.program in $localConfig"
        Exit-DotfilesModule
    }
    if ($current) {
        Add-DotfilesRestoreRecord @("& git config --file $(ConvertTo-PowerShellLiteral $localConfig) gpg.program $(ConvertTo-PowerShellLiteral $current)")
    } elseif ($existed) {
        Add-DotfilesRestoreRecord @("& git config --file $(ConvertTo-PowerShellLiteral $localConfig) --unset gpg.program")
    } else {
        Add-DotfilesRestoreRecord @("[IO.File]::Delete($(ConvertTo-PowerShellLiteral $localConfig))")
    }
    Write-DotfilesLog success "Set gpg.program to $gpg in $localConfig"
}

if ($script:DotfilesErrors -eq 0) { Write-DotfilesLog success 'Git setup checked' }
Exit-DotfilesModule
