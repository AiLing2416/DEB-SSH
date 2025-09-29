#!/bin/bash

# ==============================================================================
# SSH Alias Management Script (sshm)
# Description: A tool to easily add, remove, modify, list, and connect to SSH hosts.
#              Features smart IP address and port handling.
# Author: Gemini
# ==============================================================================

# --- Configuration ---
# NOTE: IPv6 compression in list_hosts relies on python3 being installed.
SSH_DIR="$HOME/.ssh"
CONFIG_FILE="$SSH_DIR/config"
KEYS_DIR="$SSH_DIR/jump_keys"

# --- Colors ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'

# --- Helper Functions ---

initialize() {
    mkdir -p "$SSH_DIR" "$KEYS_DIR"
    touch "$CONFIG_FILE"
    chmod 700 "$SSH_DIR" "$KEYS_DIR"
    chmod 600 "$CONFIG_FILE"
}

die() {
    echo -e "\n${C_RED}错误: $1${C_RESET}" >&2
    exit 1
}

success() {
    echo -e "${C_GREEN}$1${C_RESET}"
}

info() {
    echo -e "${C_CYAN}$1${C_RESET}"
}

prompt() {
    echo -e "${C_YELLOW}$1${C_RESET}"
}

# --- Core Functions ---

list_hosts() {
    info "--- SSH Host Configurations ---"
    if [ ! -s "$CONFIG_FILE" ] || ! grep -q -E "^\s*Host\s+" "$CONFIG_FILE"; then
        echo "No hosts configured."
        info "-------------------------------"
        return
    fi
    
    awk '
        function print_host() {
            if (host && host != "*") {
                if (hostname ~ /:/ && system("command -v python3 >/dev/null 2>&1") == 0) {
                    cmd = "python3 -c \"import ipaddress; print(ipaddress.ip_address(\\\"" hostname "\\\").compressed)\" 2>/dev/null";
                    if ((cmd | getline compressed_hostname) > 0) {
                        hostname = compressed_hostname;
                    }
                    close(cmd);
                }
                
                # FEATURE: Append port to hostname if not default 22
                display_name = hostname;
                if (port != 22) {
                    display_name = hostname ":" port;
                }

                auth_method = keyfile ? "密钥 (Key)" : "密码 (Password)";
                printf "  %-16s -> %s@%s (%s)\n", host, user, display_name, auth_method;
            }
        }
        $1 == "Host" {
            print_host();
            host = $2;
            user = "n/a";
            hostname = "n/a";
            port = "22"; # FEATURE: Default port is 22
            keyfile = "";
        }
        $1 == "HostName" { hostname = $2 }
        $1 == "User" { user = $2 }
        $1 == "Port" { port = $2 } # FEATURE: Read Port directive
        $1 == "IdentityFile" { keyfile = $2 }
        END { print_host() }
    ' "$CONFIG_FILE"
    
    info "-------------------------------"
}

# Function to handle IPv4 address shorthand completion
format_hostname() {
    local hostname_in=$1
    if [[ "$hostname_in" =~ ^[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local first_octet; first_octet=$(echo "$hostname_in" | cut -d. -f1)
        local last_octet; last_octet=$(echo "$hostname_in" | cut -d. -f2)
        local completed_hostname="${first_octet}.0.0.${last_octet}"
        info "IP 地址已自动补全为: $completed_hostname" >&2
        echo "$completed_hostname"
    else
        echo "$hostname_in"
    fi
}

add_host() {
    info "--- Add New Host Configuration ---"
    
    read -p "请输入新主机的别名: " alias
    [ -z "$alias" ] && die "主机别名不能为空。"
    if grep -q -E "^\s*Host\s+$alias\s*$" "$CONFIG_FILE"; then
        die "主机别名 '$alias' 已存在。"
    fi

    read -p "请输入远程主机地址 (Hostname / IP): " hostname_input
    [ -z "$hostname_input" ] && die "主机地址不能为空。"
    hostname=$(format_hostname "$hostname_input")

    read -p "请输入登录用户名: " user
    [ -z "$user" ] && die "用户名不能为空。"

    # FEATURE: Add port selection
    read -p "请输入 SSH 端口 (默认为 22): " port
    port=${port:-22}
    if [[ ! "$port" =~ ^[0-9]+$ || "$port" -lt 1 || "$port" -gt 65535 ]]; then
        die "无效的端口号 '$port'。请输入 1-65535 之间的数字。"
    fi

    prompt "请粘贴您的私钥内容，然后按 CTRL+D 确认。"
    prompt "(如果希望使用密码登录，请直接按 CTRL+D)"
    local key_data; key_data=$(cat)
    
    local identity_file_line=""
    if [ -n "$key_data" ]; then
        local new_key_path="$KEYS_DIR/${alias}_id"
        echo "$key_data" > "$new_key_path" || die "无法写入密钥文件。"
        chmod 600 "$new_key_path"
        identity_file_line="    IdentityFile $new_key_path"
        success "私钥已保存至 $new_key_path 并已配置。"
    else
        info "未提供私钥。此主机将配置为使用密码认证。"
    fi

    {
        echo ""; echo "Host $alias"; echo "    HostName $hostname"; echo "    User $user";
        # FEATURE: Only add Port directive if it's not the default
        if [ "$port" -ne 22 ]; then
            echo "    Port $port"
        fi
        [ -n "$identity_file_line" ] && echo "$identity_file_line";
    } >> "$CONFIG_FILE"

    success "主机 '$alias' 添加成功。"
    echo; list_hosts
}

remove_host() {
    read -p "请输入要移除的主机别名: " alias
    [ -z "$alias" ] && die "主机别名不能为空。"
    if ! grep -q -E "^\s*Host\s+$alias\s*$" "$CONFIG_FILE"; then
        die "主机 '$alias' 未找到。"
    fi

    local key_file="$KEYS_DIR/${alias}_id"
    if [ -f "$key_file" ]; then
        rm -f "$key_file"; success "已移除关联的密钥文件: $key_file"
    fi

    awk -v alias="$alias" 'BEGIN{p=1} $1=="Host"&&$2==alias{p=0} $1=="Host"&&$2!=alias{p=1} !NF&&p==0{next} p{print}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    success "主机 '$alias' 的配置已成功移除。"
    echo; list_hosts
}

connect_host() {
    read -p "请输入要连接的主机别名: " alias
    [ -z "$alias" ] && die "主机别名不能为空。"
    if ! grep -q -E "^\s*Host\s+$alias\s*$" "$CONFIG_FILE"; then die "主机 '$alias' 未找到。"; fi
    info "正在尝试连接到 '$alias'..."; ssh "$alias"
}

modify_host() {
    read -p "请输入要修改的主机别名: " alias
    [ -z "$alias" ] && die "主机别名不能为空。"
    if ! grep -q -E "^\s*Host\s+$alias\s*$" "$CONFIG_FILE"; then die "主机 '$alias' 未找到。"; fi

    info "--- Modify Host: $alias ---"; prompt "(直接按 Enter 表示不修改)"

    local current_hostname; current_hostname=$(awk "/^Host ${alias}$/{f=1} f&&/HostName/{print \$2; exit}" "$CONFIG_FILE")
    local current_user; current_user=$(awk "/^Host ${alias}$/{f=1} f&&/User/{print \$2; exit}" "$CONFIG_FILE")
    # FEATURE: Get current port, default to 22 if not specified
    local current_port; current_port=$(awk "/^Host ${alias}$/{f=1} f&&/Port/{print \$2; exit}" "$CONFIG_FILE")
    current_port=${current_port:-22}
    local current_keyfile; current_keyfile=$(awk "/^Host ${alias}$/{f=1} f&&/IdentityFile/{print \$2; exit}" "$CONFIG_FILE")
    
    read -p "新主机地址 (当前: $current_hostname): " new_hostname_input
    local final_hostname_input=${new_hostname_input:-$current_hostname}
    new_hostname=$(format_hostname "$final_hostname_input")
    
    read -p "新用户名 (当前: $current_user): " new_user
    new_user=${new_user:-$current_user}

    # FEATURE: Modify port
    read -p "新 SSH 端口 (当前: $current_port): " new_port_input
    new_port=${new_port_input:-$current_port}
    if [[ ! "$new_port" =~ ^[0-9]+$ || "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
        die "无效的端口号 '$new_port'。请输入 1-65535 之间的数字。"
    fi

    local new_identity_file_line=""
    if [ -n "$current_keyfile" ]; then
        info "当前认证方式为: 密钥 (Key)"; new_identity_file_line="    IdentityFile $current_keyfile"
    else info "当前认证方式为: 密码 (Password)"; fi
    
    read -p "认证方式: [K]eep 保留, [U]pdate/Add 更新/添加密钥, [R]emove 移除密钥 (使用密码): " -n 1 -r auth_choice; echo
    case "$auth_choice" in
        [uU])
            prompt "请粘贴新的私钥内容，然后按 CTRL+D 确认。"
            local key_data; key_data=$(cat)
            if [ -n "$key_data" ]; then
                local new_key_path="$KEYS_DIR/${alias}_id"
                echo "$key_data" > "$new_key_path" || die "无法写入密钥文件。"
                chmod 600 "$new_key_path"; new_identity_file_line="    IdentityFile $new_key_path"
                success "私钥已更新并保存至 $new_key_path"
            else info "未提供新密钥，认证方式保持不变。"; fi ;;
        [rR])
            if [ -f "$current_keyfile" ]; then rm -f "$current_keyfile"; success "已移除密钥文件: $current_keyfile"; fi
            new_identity_file_line=""; info "主机将配置为使用密码认证。" ;;
        [kK]|"") info "认证方式保持不变。" ;;
        *) info "无效选择，认证方式保持不变。" ;;
    esac

    awk -v alias="$alias" 'BEGIN{p=1} $1=="Host"&&$2==alias{p=0} $1=="Host"&&$2!=alias{p=1} !NF&&p==0{next} p{print}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    { 
        echo ""; echo "Host $alias"; echo "    HostName $new_hostname"; echo "    User $new_user"; 
        if [ "$new_port" -ne 22 ]; then echo "    Port $new_port"; fi
        [ -n "$new_identity_file_line" ] && echo "$new_identity_file_line"; 
    } >> "$CONFIG_FILE"

    success "主机 '$alias' 的配置已更新。"
    echo; list_hosts
}


usage() {
    echo -e "${C_YELLOW}SSH 主机管理脚本 (sshm)${C_RESET}"
    echo "一个用于简化 ~/.ssh/config 管理的命令行工具，支持智能 IP 和端口处理。"
    echo
    echo "用法: sshm [参数]"
    echo
    echo "参数:"
    echo -e "  ${C_GREEN}-a, --add${C_RESET}      交互式添加一个新的远程主机。"
    echo -e "  ${C_GREEN}-l, --list${C_RESET}      显示所有已配置主机的详细列表。"
    echo -e "  ${C_GREEN}-c, --connect${C_RESET}   连接到一个指定的主机。"
    echo -e "  ${C_GREEN}-r, --remove${C_RESET}    从配置中移除一个指定的主机。"
    echo -e "  ${C_GREEN}-m, --modify${C_RESET}    交互式修改一个已存在的主机信息。"
    echo -e "  ${C_GREEN}-h, --help${C_RESET}      显示此帮助信息。"
    echo
}

# --- Main Logic & Argument Parsing ---

initialize
if [ $# -eq 0 ]; then usage; exit 1; fi

case "$1" in
    -a|--add) add_host ;;
    -l|--list) list_hosts ;;
    -c|--connect) connect_host ;;
    -r|--remove) remove_host ;;
    -m|--modify) modify_host ;;
    -h|--help) usage ;;
    *) echo -e "${C_RED}未知参数: $1${C_RESET}"; usage; exit 1 ;;
esac

exit 0
