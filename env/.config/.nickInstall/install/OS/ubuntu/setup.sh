#!/bin/bash
source ./packages.sh

# Enable and start the mysql service 
sudo systemctl enable --now mysql.service

# pull https://github.com/nick22985.keys from github if the key does not exists in ~.ssh/authorized_keys then add it
if ! [ -f ~/.ssh/authorized_keys ]; then
	echo "Adding ssh dir"
	mkdir ~/.ssh
fi


# Download the keys from git and loop over each key
KEY_URL="https://github.com/nick22985.keys"
AUTHORIZED_KEYS_FILE="$HOME/.ssh/authorized_keys"
curl -sSL "$KEY_URL" | while read key; do
		# Check if the key already exists in the authorized_keys file
		if grep -q "$key" "$AUTHORIZED_KEYS_FILE"; then
		echo "Key already exists in $AUTHORIZED_KEYS_FILEFILE"
	else
		# Add the key to the authorized_keys file
		echo "$key" | tee -a "$AUTHORIZED_KEYS_FILE"
		echo "Key added to $AUTHORIZED_KEYS_FILE"
	fi
done

# Fixes GULP: The 'ENOSPC' error
 if ! grep -lq 'fs.inotify.max_user_watches=9999999' /etc/sysctl.conf; then
	 echo "Setting max_user_watches to 9999999"
	 echo fs.inotify.max_user_watches=9999999 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
 fi
 if ! grep -lq 'fs.inotify.max_queued_events=9999999' /etc/sysctl.conf; then
	 echo "Setting max_queued_events to 9999999"
	 echo fs.inotify.max_queued_events=9999999 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
 fi

 
# Needs to be added to /etc/security/limits.conf
# *               soft    nofile            10000
# *               hard    nofile            10000 
