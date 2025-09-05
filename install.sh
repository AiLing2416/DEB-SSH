#!/bin/bash

# DEB-SSH Installer
# Version: 2.0 (Refactored)
# Description: Installs the deb-ssh CLI tool locally.
# Run: bash install.sh

CLI_PATH="/usr/local/bin/deb-ssh"
LOG_FILE="$HOME/deb-ssh.log"

function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

function check_os() {
    if ! grep -iqE 'debian|ubuntu' /etc/os-release; then
        log "ERROR: This script is for Debian/Ubuntu."
        exit 1
    fi
}

function install_cli() {
    if [ ! -w "/usr/local/bin" ]; then
        echo "Requires sudo to install to /usr/local/bin."
        sudo bash -c "$(declare -f create_cli_script); create_cli_script '$CLI_PATH'"
    else
        create_cli_script "$CLI_PATH"
    fi
    chmod +x "$CLI_PATH"
    log "deb-ssh CLI installed at $CLI_PATH. Run 'deb-ssh --help' for usage."
}

function create_cli_script() {
    local path="$1"
    cat > "$path" << 'EOF'
#!/bin/bash

# DEB-SSH CLI Tool
# Version: 2.0
# Commands:
#   install                Install SSH server (requires sudo)
#   keys generate          Generate RSA key pair for current user
#   keys add <pubkey>      Add public key to current user's authorized_keys
#   port <number>          Set SSH port (requires sudo, default 22)
#   jump add --host <h> --port <p> --user <u> --key <k>  Add jump host config to ~/.ssh/config
#   jump list              List current user's jump configs
#   --help                 Show this help

LOG_FILE="$HOME/deb-ssh.log"
function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

function check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        log "ERROR: This command requires sudo."
        exit 1
    fi
}

function install_ssh() {
    check_sudo
    if ! command -v sshd >/dev/null 2>&1; then
        log "Installing OpenSSH server..."
        apt update -y || { log "ERROR: apt update failed."; exit 1; }
        apt install openssh-server -y || { log "ERROR: Installation failed."; exit 1; }
        systemctl enable ssh
        systemctl start ssh
        log "SSH server installed and started."
    else
        log "SSH server already installed."
    fi
}

function generate_keys() {
    local key_path="$HOME/.ssh/id_rsa"
    mkdir -p "$HOME/.ssh"
    if [ -f "$key_path" ]; then
        read -p "Existing key found. Overwrite? (y/n): " confirm
        [[ "$confirm" != "y" ]] && { log "Skipped."; return; }
    fi
    ssh-keygen -t rsa -b 4096 -f "$key_path" -N "" || { log "ERROR: Failed."; exit 1; }
    chmod 600 "$key_path"
    chmod 644 "$key_path.pub"
    log "Key pair generated at $key_path. Public: $(cat "$key_path.pub")"
}

function add_pubkey() {
    local pubkey="$1"
    [ -z "$pubkey" ] && { log "ERROR: Pubkey required."; exit 1; }
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"
    if grep -q "$pubkey" "$HOME/.ssh/authorized_keys"; then
        log "Key already added."
    else
        echo "$pubkey" >> "$HOME/.ssh/authorized_keys"
        chmod 600 "$HOME/.ssh/authorized_keys"
        log "Key added."
    fi
}

function set_port() {
    check_sudo
    local port="$1"
    [[ ! "$port" =~ ^[0-9]+$ || "$port" -lt 1 || "$port" -gt 65535 ]] && { log "ERROR: Invalid port."; exit 1; }
    sed -i "s/^#Port .*/Port $port/" /etc/ssh/sshd_config
    sed -i "s/^Port .*/Port $port/" /etc/ssh/sshd_config
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$port"/tcp
        ufw reload
        log "UFW updated."
    fi
    systemctl restart ssh
    log "Port set to $port."
}

function add_jump() {
    local host="" port="22" user="$USER" key="$HOME/.ssh/id_rsa"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host) host="$2"; shift 2 ;;
            --port) port="$2"; shift 2 ;;
            --user) user="$2"; shift 2 ;;
            --key) key="$2"; shift 2 ;;
            *) log "ERROR: Invalid option."; exit 1 ;;
        esac
    done
    [ -z "$host" ] && { log "ERROR: --host required."; exit 1; }
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    {
        echo ""
        echo "Host $host"
        echo "  HostName $host"
        echo "  Port $port"
        echo "  User $user"
        echo "  IdentityFile $key"
        echo "  ProxyJump none  # Example bastion config"
    } >> "$HOME/.ssh/config"
    log "Jump host $host added to ~/.ssh/config."
}

function list_jump() {
    if [ -f "$HOME/.ssh/config" ]; then
        grep -E '^Host ' "$HOME/.ssh/config" || log "No jump hosts found."
    else
        log "No config file."
    fi
}

function show_help() {
    grep '^# ' "$0" | sed 's/^# //'
    exit 0
}

case "$1" in
    install) install_ssh ;;
    keys)
        case "$2" in
            generate) generate_keys ;;
            add) add_pubkey "$3" ;;
            *) log "ERROR: Invalid keys subcommand."; show_help ;;
        esac
        ;;
    port) set_port "$2" ;;
    jump)
        case "$2" in
            add) shift 2; add_jump "$@" ;;
            list) list_jump ;;
            *) log "ERROR: Invalid jump subcommand."; show_help ;;
        esac
        ;;
    --help) show_help ;;
    *) log "ERROR: Unknown command."; show_help ;;
esac

log "Operation completed. Log: $LOG_FILE"
EOF
}

check_os
install_cli
