$USERPROFILE = Get-Content $PROFILE


$configFunction = 'function config {& "$env:ProgramFiles\Git\bin\git.exe" --git-dir="$env:userprofile\.dotfiles\" --work-tree="$env:userprofile\" $args}'


if ($USERPROFILE -contains $configFunction) {
	Write-host "config function already exists"
} else {
	Write-host "Installing config function"
	Add-Content -Path $PROFILE -Value $configFunction
}
