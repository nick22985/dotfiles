#!/bin/bash
# check if ~/.dotfiles folder exists

if [ -d "$HOME/.dotfiles" ]; then
	echo "dotfiles folder exists"
else
	echo "dotfiles folder does not exist"
	echo "cloning dotfiles repo"
	git clone --bare https://github.com/nick22985/dotfiles $HOME/.dotfiles
fi

# checkout the actual content from the bare repository to $HOME
git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME checkout 

# set the flag showUntrackedFiles to no on this specific (local) repository
git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME config --local status.showUntrackedFiles no

# get the user to set a ssh key ssh-keygen -t rsa -b 4096 -C "email@example.com"
read -p "Enter your email address: " email

# setup ssh key
ssh-keygen -t ed25519 -C "$email" -f ~/.ssh/id_ed25519 && eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519 && echo "Add ssh key to github: " && cat ~/.ssh/id_ed25519.pub 

# set .dotfiles repo to ssh url
git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME remote set-url origin git@github.com:nick22985/dotfiles.git


