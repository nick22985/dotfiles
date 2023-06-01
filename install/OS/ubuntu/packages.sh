#!bin/bash
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt-get install -y zsh exa neovim gh git snapd-xdg-open snapd ripgrep neofetch htop nvtop mysql-server

# Install fish
if ! [ -x "$(command -v fish)" ]; then
	echo "Installing fish shell"
	curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher && fisher install jorgebucaran/nvm.fish
fi

# mongodb install
# check if mongodb is installed
if ! [ -x "$(command -v mongod)" ]; then
	sudo apt-get install gnupg
	curl -fsSL https://pgp.mongodb.com/server-6.0.asc | \
	sudo gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg \
		--dearmor
	echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
	sudo apt-get update
	sudo apt-get install -y mongodb-org
	sudo systemctl enable mongodb
	sudo systemctl start mongodb
fi

# Install Starship
if ! [ -x "$(command -v starship)" ]; then
	echo "Installing starship"
	curl -sS https://starship.rs/install.sh | sh -y
fi

# install oh-my-zsh
echo "Installing oh-my-zsh"
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# install git lfs https://git-lfs.com/

function getAppAndInstall() {
	TEMP_DEB="$(mktemp)" &&
		wget -O "$TEMP_DEB" $1 &&
		sudo dpkg -i "$TEMP_DEB"
			rm -f "$TEMP_DEB"
}

if ! [ -x "$(command -v discord)" ]; then
	echo "Installing discord"
	getAppAndInstall "https://discord.com/api/download?platform=linux&format=deb"
fi

if ! [ -x "$(command -v 1password)" ]; then
	echo "Installing 1password"
	getAppAndInstall "https://downloads.1password.com/linux/debian/amd64/stable/1password-latest.deb"
fi

if ! [ -x "$(command -v cloudflared)" ]; then
	echo "Installing cloudflared"
	getAppAndInstall "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
fi

if ! [ -x "$(command -v spotify)" ]; then
	echo "Installing spotify"
	sudo snap install spotify
fi

if ! [ -x "$(command -v slack)" ]; then
	echo "Installing slack"
	sudo snap install slack --classic
fi

if ! [ -x "$(command -v code)" ]; then
	echo "Installing vscode"
	sudo snap install code --classic
fi

if ! fc-list | grep -lq 'Nerd Font'; then
	echo "Installing nerd-fonts"
	TEMP_DIR="$(mktemp)" &&
		git clone https://github.com/ryanoasis/nerd-fonts.git
		sudo "$TEMP_DIR/install.sh"
			rm -rf "$TEMP_DIR"
fi
