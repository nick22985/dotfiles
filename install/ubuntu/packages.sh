#!bin/bash
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update 
sudo apt-get install -y zsh exa neovim gh git snapd-xdg-open snapd
	
# Install fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher && fisher install jorgebucaran/nvm.fish

# mongodb install
sudo apt-get install gnupg
curl -fsSL https://pgp.mongodb.com/server-6.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg \
   --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org

# Install Starship
curl -sS https://starship.rs/install.sh | sh -y

function getAppAndInstall() {
	TEMP_DEB="$(mktemp)" &&
		wget -O "$TEMP_DEB" $1 &&
		sudo dpkg -i "$TEMP_DEB"
			rm -f "$TEMP_DEB"
}

declare -a appUrls=("https://discord.com/api/download?platform=linux&format=deb" "https://discord.com/api/download?platform=linux&format=deb")

for i in ${appUrls[@]}; do
	echo "Installing: $i"
	getAppAndInstall $i 
done


# Install snap applications spotify, slack

