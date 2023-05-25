# Auto install

## Windows

`cmd /V /C "curl -o script.ps1 https://raw.githubusercontent.com/nick22985/dotfiles/master/scripts/install.ps1 & powershell.exe -ExecutionPolicy Bypass -File script.ps1"`

# How to clone the repo

Need to configure this as an alias to be able to checkout the bare repo into

`alias config='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'`

# Clone all submodules

`git submodule update --init --recursive`

clone bare repo and all submodules attached

`git clone --recurse-submodules --remote-submodules --bare git@github.com:nick22985/dotfiles.git $HOME/.dotfiles`

do `config checkout`

# Submodule Updating

git submodule update

### fatal: Unable to find refs/remotes/origin/HEAD revision in submodule path '.ssh'

git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master

For submodule updates
config submodule update --remote --merge

If git history is scuffed
cd .config/nvim

git fetch --all
config submodule update --remote --merge

config add .config/nvim

# Windows Alias in CMD

git --git-dir=%userprofile%/.dotfiles/ --work-tree=%userprofile% checkout

# Windows Upgrade winget

winget upgrade --all --include-unknown

# Windows now has gpg installed by default with git so external gpg is not recireved however. When importing may face issues now with git using exteranl gpg need to define it in user settings. Maybe add it to a windows specific .gitconfig?

## add to .gitconfig.local have the windows install auto create this file if needed. If we decided not to use the inbuilt git one

[gpg]
program = C:\\Users\\username\\gpg-no-tty.sh

## whever the location is of GPG program

git config --global gpg.program "%PROGRAMFILES(x86)%\GnuPG\bin\gpg.exe"
