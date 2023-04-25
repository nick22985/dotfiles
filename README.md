# How to clone the repo
git clone --recurse-submodules --remote-submodules git@github.com:nick22985/dotfiles.git

alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
git clone --recurse-submodules --remote-submodules --bare git@github.com:nick22985/dotfiles.git $HOME/.cfg

# Submodule Updating
git submodule init
git submodule update