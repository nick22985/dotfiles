#!/usr/bin/env bash
# Shared by modules/syncthing (the machines that work in the folders) and modules/syncthing-relay
# (an always-on machine that keeps an encrypted copy for when the others are off).

private_dir="$DOTFILES_DIR/env/.config/.nickInstall/install/configs/private"
machines_file="$private_dir/machines.txt"
syncthing_dir="$DOTFILES_DIR/modules/syncthing"
folders_file="$syncthing_dir/folders.tsv"

# Fill folders with "id|path below $HOME|ignore file|relay mode" from folders.tsv; returns 1 for
# invalid lines.
syncthing_read_folders() {
    local folder_id relative ignore_name relay_mode extra result=0
    folders=()
    while IFS='|' read -r folder_id relative ignore_name relay_mode extra; do
        [[ -n "${folder_id:-}" && "$folder_id" != \#* ]] || continue
        if [[ -n "${extra:-}" || ! "$folder_id" =~ ^[a-z0-9-]+$ || -z "${relative:-}" || "$relative" == /* || "$relative" == *..* \
            || ( "$ignore_name" != "-" && ! -f "$syncthing_dir/$ignore_name" ) \
            || ( "${relay_mode:-}" != "encrypted" && "${relay_mode:-}" != "plain" ) ]]; then
            log_error "Invalid entry in $folders_file: $folder_id|${relative:-}|${ignore_name:-}|${relay_mode:-}"
            result=1
            continue
        fi
        folders+=("$folder_id|$relative|$ignore_name|$relay_mode")
    done < "$folders_file"
    return "$result"
}

# Print the .stignore for folder $1 with ignore file $2 (from folders.tsv) on this machine.
syncthing_print_ignores() {
    local folder_id="$1" ignore_name="$2"
    if [[ "$folder_id" == "projects" ]]; then
        # Adds the bare-layout repository patterns; git-peer-sync and modules/sync-repos keep them current.
        "$DOTFILES_DIR/env/.local/bin/projects-stignore" --print
    elif [[ "$folder_id" == "dotfiles" ]]; then
        # Adds the repository's gitignore rules; git-peer-sync keeps them current.
        "$DOTFILES_DIR/env/.local/bin/dotfiles-stignore" --print
    else
        cat -- "$syncthing_dir/$ignore_name"
    fi
}

# Install folder path $1's .stignore from the content in file $3 with a receipt backup ($2 names its
# source in messages). It must be in place before the folder exists, or the first scan shares
# everything.
syncthing_install_ignores() {
    local path="$1" source_name="$2" ignore_file="$3" ignore_target="$1/.stignore" backup
    if [[ -f "$ignore_target" && ! -L "$ignore_target" ]] && cmp -s -- "$ignore_file" "$ignore_target"; then
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "Would write $ignore_target from $source_name"
        return 0
    fi
    mkdir -p -m 700 "$path"
    backup="$DOTFILES_RECEIPT_DIR/backups/user/${ignore_target#"$HOME"/}"
    if [[ -e "$ignore_target" || -L "$ignore_target" ]]; then
        mkdir -p "$(dirname "$backup")"
        mv -- "$ignore_target" "$backup" || return 1
        receipt_add_restore user "$(printf 'rm -f -- %q\nmv -- %q %q' "$ignore_target" "$backup" "$ignore_target")"
    else
        receipt_add_restore user "$(printf 'rm -f -- %q' "$ignore_target")"
    fi
    cp -- "$ignore_file" "$ignore_target" || return 1
    log_success "Installed $ignore_target"
}

# Whether some folder in folders.tsv goes to the relays readable (they can't be marked untrusted then).
syncthing_has_plain_folders() {
    local folder
    for folder in "${folders[@]}"; do
        [[ "${folder##*|}" == "plain" ]] && return 0
    done
    return 1
}

# The CLI talks to the running instance; give a freshly started service time to open its API.
syncthing_wait_for_api() {
    for _ in {1..30}; do
        syncthing cli show system >/dev/null 2>&1 && return 0
        sleep 1
    done
    log_error "Syncthing is not responding (check: systemctl --user status syncthing)"
    return 1
}

# Machines reach each other at their SSH host (Tailscale) or through LAN discovery at home; relays,
# global discovery and NAT traversal would only tell third-party servers about this machine.
syncthing_disable_public_services() {
    local option result=0
    for option in relays-enabled global-ann-enabled natenabled; do
        if [[ "$(syncthing cli config options "$option" get)" != "false" ]]; then
            syncthing cli config options "$option" set false || result=1
        fi
    done
    return "$result"
}

# Read machines.txt lines "name device-id ssh-host [relay]" into trusted_peers and relay_peers
# ("device-id|name|ssh-host", without this machine) and set this_role to trusted, relay or "" when
# this machine is not listed. Returns 1 for invalid lines.
# shellcheck disable=SC2034 # the arrays and this_role are read by the install scripts
syncthing_read_machines() {
    local my_id="$1" name device_id ssh_host role extra result=0
    trusted_peers=()
    relay_peers=()
    this_role=""
    while read -r name device_id ssh_host role extra; do
        [[ -n "${name:-}" && "$name" != \#* ]] || continue
        if [[ -n "${extra:-}" || -z "${ssh_host:-}" || ! "${device_id:-}" =~ ^[A-Z0-9]{7}(-[A-Z0-9]{7}){7}$ \
            || ( -n "${role:-}" && "$role" != "relay" ) ]]; then
            log_error "Invalid entry in $machines_file: $name ${device_id:-} ${ssh_host:-} ${role:-} ${extra:-}"
            result=1
            continue
        fi
        if [[ "$device_id" == "$my_id" ]]; then
            this_role="${role:-trusted}"
        elif [[ "${role:-}" == "relay" ]]; then
            relay_peers+=("$device_id|$name|$ssh_host")
        else
            trusted_peers+=("$device_id|$name|$ssh_host")
        fi
    done < "$machines_file"
    return "$result"
}

# Add a peer from syncthing_read_machines unless Syncthing already knows it; with "untrusted" it
# only ever receives encrypted data. Returns 1 when the device could not be added or updated.
syncthing_add_device() {
    local peer="$1" trust="${2:-}" device_id name ssh_host untrusted=false address key
    IFS='|' read -r device_id name ssh_host <<< "$peer"
    [[ "$trust" == "untrusted" ]] && untrusted=true
    address="tcp://$ssh_host:22000"
    if syncthing cli config devices list | grep -Fxq -- "$device_id"; then
        if [[ "$(syncthing cli config devices "$device_id" untrusted get)" != "$untrusted" ]]; then
            syncthing cli config devices "$device_id" untrusted set "$untrusted" || return 1
            log_success "Marked device $name as ${trust:-trusted}"
        fi
        # A device accepted in the GUI only has "dynamic", which finds it on the LAN but not away.
        while read -r key; do
            [[ "$(syncthing cli config devices "$device_id" addresses "$key" get)" == "$address" ]] && return 0
        done < <(syncthing cli config devices "$device_id" addresses list)
        syncthing cli config devices "$device_id" addresses add "$address" || return 1
        log_success "Added address $address for device $name"
        return 0
    fi
    # Dial the SSH host (a Tailscale name works anywhere) first, then fall back to discovery.
    syncthing cli config devices add-json \
        "$(printf '{"deviceID":"%s","name":"%s","addresses":["%s","dynamic"],"untrusted":%s}' "$device_id" "$name" "$address" "$untrusted")" \
        || return 1
    log_success "Added device $name"
}
