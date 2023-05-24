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

For submodule updates
config submodule update --remote --merge

If git history is scuffed
cd .config/nvim
git fetch --all
config submodule update --remote --merge

config add .config/nvim

# Windows Upgrade winget

winget upgrade --all --include-unknown
