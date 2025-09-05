#!/bin/bash

# ==============================================================================
# 脚本名称: setup_ed25519_key.sh
# 描述:     一个用于自动生成 ED25519 密钥对并为当前用户配置 SSH 登录的脚本。
#           支持交互式和命令行两种模式。
# 作者:     Gemini
# 日期:     2025-09-05
# ==============================================================================

# --- 全局变量和颜色定义 ---
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# --- 函数定义 ---

# 显示帮助信息
function display_usage() {
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -c, --comment <comment>   为新密钥提供注释 (非交互模式)"
    echo "  -p, --password <password> 为新密钥设置密码 (非交互模式)。留空则无密码。"
    echo "  -y, --yes-disable-pw      在完成后自动禁用密码登录 (需要sudo权限)。"
    echo "  -h, --help                显示此帮助信息。"
    echo
    echo "如果不带任何选项运行，脚本将进入交互模式。"
}

# 检查并创建 .ssh 目录和 authorized_keys 文件
function ensure_ssh_dir() {
    local ssh_dir="$HOME/.ssh"
    local auth_keys_file="$ssh_dir/authorized_keys"

    if [ ! -d "$ssh_dir" ]; then
        echo -e "${YELLOW}检测到 ~/.ssh 目录不存在，正在创建...${NC}"
        mkdir -p "$ssh_dir"
    fi
    if [ ! -f "$auth_keys_file" ]; then
        echo -e "${YELLOW}检测到 authorized_keys 文件不存在，正在创建...${NC}"
        touch "$auth_keys_file"
    fi
    
    # 始终确保权限正确
    chmod 700 "$ssh_dir"
    chmod 600 "$auth_keys_file"
    echo -e "${GREEN}✓ ~/.ssh 目录和 authorized_keys 文件权限已正确配置。${NC}"
}

# 禁用密码登录
function disable_password_login() {
    local sshd_config="/etc/ssh/sshd_config"
    echo -e "${YELLOW}正在尝试禁用密码登录...${NC}"

    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 此操作需要 root 权限。请使用 'sudo' 运行此脚本。${NC}"
        return 1
    fi

    # 备份配置文件
    sudo cp "$sshd_config" "${sshd_config}.bak.$(date +%F)"
    echo "已备份 sshd_config 文件到 ${sshd_config}.bak.$(date +%F)"

    # 禁用密码登录
    sudo sed -i -E 's/^[#\s]*PasswordAuthentication\s+(yes|no)/PasswordAuthentication no/' "$sshd_config"
    # 确保 ChallengeResponseAuthentication 也被禁用，它在某些系统上会触发密码提示
    sudo sed -i -E 's/^[#\s]*ChallengeResponseAuthentication\s+(yes|no)/ChallengeResponseAuthentication no/' "$sshd_config"
    
    echo -e "${GREEN}✓ 配置文件 /etc/ssh/sshd_config 已更新。${NC}"

    # 重启 sshd 服务
    echo "正在尝试重启 SSH 服务..."
    if command -v systemctl &> /dev/null; then
        sudo systemctl restart sshd
    elif command -v service &> /dev/null; then
        sudo service ssh restart
    else
        echo -e "${RED}无法确定如何重启 SSH 服务。请手动重启 (例如: 'sudo systemctl restart sshd')。${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ SSH 服务已成功重启。密码登录现已禁用。${NC}"
    echo -e "${YELLOW}警告: 请确保您的密钥已正确配置并且可以登录，否则您可能会被锁定在系统之外！${NC}"
}


# --- 主逻辑 ---
main() {
    # 命令行参数解析
    local comment=""
    local passphrase=""
    local auto_disable_pw=false
    local interactive_mode=true

    # 如果有任何参数，则切换到非交互模式
    if [ "$#" -gt 0 ]; then
        interactive_mode=false
    fi

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -c|--comment) comment="$2"; shift ;;
            -p|--password) passphrase="$2"; shift ;;
            -y|--yes-disable-pw) auto_disable_pw=true ;;
            -h|--help) display_usage; exit 0 ;;
            *) echo -e "${RED}未知选项: $1${NC}"; display_usage; exit 1 ;;
        esac
        shift
    done

    ensure_ssh_dir

    # --- 交互模式 ---
    if [ "$interactive_mode" = true ]; then
        read -p "是否要生成新的 ED25519 密钥对? (y/N): " choice
        case "$choice" in
            y|Y|是)
                # --- 生成新密钥 ---
                read -p "请输入密钥注释 (例如 your_email@example.com): " comment
                comment=${comment:-$(whoami)@$(hostname)}
                
                read -s -p "请输入可选的密钥密码 (留空则无密码): " passphrase
                echo
                read -s -p "请再次输入密码以确认: " passphrase2
                echo
                if [ "$passphrase" != "$passphrase2" ]; then
                    echo -e "${RED}两次输入的密码不匹配。操作已中止。${NC}"
                    exit 1
                fi

                # 创建临时备份目录
                local backup_dir="$HOME/ed25519_$(date +%Y-%m-%d)"
                mkdir -p "$backup_dir"
                local key_path="$backup_dir/id_ed25519"

                echo -e "${YELLOW}正在生成 ED25519 密钥对...${NC}"
                ssh-keygen -t ed25519 -C "$comment" -N "$passphrase" -f "$key_path"

                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ 密钥对已成功生成。${NC}"
                    echo "公钥为:"
                    cat "${key_path}.pub"
                    
                    # 配置登录
                    cat "${key_path}.pub" >> "$HOME/.ssh/authorized_keys"
                    echo -e "${GREEN}✓ 公钥已自动添加到 ~/.ssh/authorized_keys。${NC}"
                    echo -e "${YELLOW}重要: 私钥已保存到: ${key_path}${NC}"
                    echo -e "${YELLOW}请务必妥善备份此私钥文件！${NC}"
                else
                    echo -e "${RED}密钥生成失败。请检查 ssh-keygen 命令和权限。${NC}"
                    exit 1
                fi
                ;;
            *)
                # --- 使用现有公钥 ---
                echo "好的，将使用您提供的现有公钥。"
                echo "请粘贴您的公钥内容，然后按 Ctrl + D 结束输入:"
                local temp_pub_key
                temp_pub_key=$(cat)

                if [ -z "$temp_pub_key" ]; then
                    echo -e "${RED}没有检测到输入。操作已中止。${NC}"
                    exit 1
                fi
                
                # 追加到 authorized_keys
                echo "$temp_pub_key" >> "$HOME/.ssh/authorized_keys"
                # 去重（可选但推荐）
                sort -u "$HOME/.ssh/authorized_keys" -o "$HOME/.ssh/authorized_keys"
                echo -e "${GREEN}✓ 提供的公钥已添加到 ~/.ssh/authorized_keys。${NC}"
                ;;
        esac

        # 询问是否禁用密码登录
        read -p "配置完成。是否要禁用服务器的密码登录？ (y/N): " disable_choice
        if [[ "$disable_choice" =~ ^[yY是]$ ]]; then
            disable_password_login
        else
            echo "已跳过禁用密码登录。您仍然可以使用密码登录。"
        fi

    # --- 非交互模式 ---
    else
        echo "运行在非交互模式..."
        if [ -z "$comment" ]; then
            comment="$(whoami)@$(hostname)"
            echo "未提供注释，使用默认值: $comment"
        fi

        # 创建临时备份目录
        local backup_dir="$HOME/ed25519_$(date +%Y-%m-%d)"
        mkdir -p "$backup_dir"
        local key_path="$backup_dir/id_ed25519"

        echo -e "${YELLOW}正在生成 ED25519 密钥对...${NC}"
        ssh-keygen -t ed25519 -C "$comment" -N "$passphrase" -f "$key_path"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 密钥对已成功生成。${NC}"
            cat "${key_path}.pub" >> "$HOME/.ssh/authorized_keys"
            echo -e "${GREEN}✓ 公钥已自动添加到 ~/.ssh/authorized_keys。${NC}"
            echo -e "${YELLOW}重要: 私钥已保存到: ${key_path}${NC}"
        else
            echo -e "${RED}密钥生成失败。${NC}"
            exit 1
        fi

        if [ "$auto_disable_pw" = true ]; then
            disable_password_login
        fi
    fi

    echo -e "\n${GREEN}===== 所有操作已完成 =====${NC}"
    echo "现在您应该可以使用 SSH 密钥从其他机器登录了。"
    echo "例如: ssh -i /path/to/your/private_key $(whoami)@$(hostname -I | awk '{print $1}')"
}

# 脚本入口
main "$@"
