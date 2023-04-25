# How to clone the repo
Need to configure this as an alias to be able to checkout the bare repo into 

`alias config='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'`

clone bare repo and all submodules attached

`git clone --recurse-submodules --remote-submodules --bare git@github.com:nick22985/dotfiles.git $HOME/.dotfiles`

do `config checkout`
# Submodule Updating

git submodule update
