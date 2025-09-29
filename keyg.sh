#!/bin/bash

# ==============================================================================
# 脚本名称: keyg.sh
# 描述:     一个用于自动生成 ED25519 密钥对并为当前用户配置 SSH 登录的脚本。
#           增加了环境检测(云平台/共享主机)和关键操作安全警告。
# 作者:     Gemini
# ==============================================================================

# --- 全局变量和颜色定义 ---
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# --- 全局状态变量 ---
PUBLIC_IPV4="N/A"
PUBLIC_IPV6="N/A"
ENVIRONMENT="standard" # standard, cloud, shared_host

# --- 函数定义 ---

# ... display_usage, get_public_ips, ensure_ssh_dir 函数与 v2 相同 ...
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

function get_public_ips() {
    echo -e "${YELLOW}正在尝试获取公网 IP 地址...${NC}"
    if ! command -v curl &> /dev/null; then
        PUBLIC_IPV4="无法获取 (curl 命令未找到)"
        PUBLIC_IPV6="无法获取 (curl 命令未找到)"
        echo -e "${RED}curl 命令未找到，无法获取公网 IP。${NC}"
        return
    fi
    local ipv4_output
    ipv4_output=$(curl -4 -sf --connect-timeout 5 https://ifconfig.me/ip)
    if [ $? -eq 0 ] && [ -n "$ipv4_output" ]; then
        PUBLIC_IPV4="$ipv4_output"
    else
        PUBLIC_IPV4="获取失败"
    fi
    local ipv6_output
    ipv6_output=$(curl -6 -sf --connect-timeout 5 https://ifconfig.me/ip)
    if [ $? -eq 0 ] && [ -n "$ipv6_output" ]; then
        PUBLIC_IPV6="$ipv6_output"
    else
        PUBLIC_IPV6="获取失败 (或服务器不支持IPv6)"
    fi
}

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
    chmod 700 "$ssh_dir"
    chmod 600 "$auth_keys_file"
    echo -e "${GREEN}✓ ~/.ssh 目录和 authorized_keys 文件权限已正确配置。${NC}"
}


# 新增：环境检测函数
function detect_environment() {
    echo -e "${YELLOW}正在检测运行环境...${NC}"
    # 检测云平台 (GCP, AWS, Azure)
    if curl -s -f -H "Metadata-Flavor: Google" --connect-timeout 2 http://metadata.google.internal > /dev/null 2>&1; then
        ENVIRONMENT="cloud"
        echo -e "${GREEN}✓ 检测到 GCP (Google Cloud) 环境。${NC}"
        return
    fi
    if curl -s -f --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id > /dev/null 2>&1; then
        ENVIRONMENT="cloud"
        echo -e "${GREEN}✓ 检测到 AWS (Amazon Web Services) 环境。${NC}"
        return
    fi
    if curl -s -f -H "Metadata: true" --connect-timeout 2 "http://169.254.169.254/metadata/instance?api-version=2021-02-01" > /dev/null 2>&1; then
        ENVIRONMENT="cloud"
        echo -e "${GREEN}✓ 检测到 Azure 环境。${NC}"
        return
    fi

    # 检测共享主机 (通过对 sshd_config 的写权限判断)
    if [ ! -w "/etc/ssh/sshd_config" ]; then
        ENVIRONMENT="shared_host"
        echo -e "${GREEN}✓ 检测到受限的运行环境 (可能是共享主机)。${NC}"
        return
    fi
    echo -e "${GREEN}✓ 未检测到特殊的云或受限环境。${NC}"
}

# 改进：禁用密码登录函数
function disable_password_login() {
    local sshd_config="/etc/ssh/sshd_config"
    echo -e "${YELLOW}准备禁用密码登录...${NC}"

    # 再次检查环境，防止被直接调用
    if [ "$ENVIRONMENT" = "cloud" ] || [ "$ENVIRONMENT" = "shared_host" ]; then
        echo -e "${RED}在此环境下，不建议或不允许通过脚本禁用密码登录。操作已中止。${NC}"
        return 1
    fi
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 此操作需要 root 权限。请使用 'sudo' 运行此脚本。${NC}"
        return 1
    fi

    # 增加最终警告和确认
    echo -e "
${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! 最终安全警告 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}
${YELLOW}此操作将修改 SSHD 配置以禁用密码登录。这是不可逆的，除非您再次手动修改配置。

1. ${RED}请绝对不要关闭当前的 SSH 会话！${NC}
2. ${YELLOW}强烈建议您现在打开一个新的终端窗口，使用下面的命令测试密钥是否能成功登录。
   测试命令: ssh -i /path/to/your/private_key $(whoami)@${PUBLIC_IPV4}
3. 确认测试成功后，再回来这里继续。

如果继续操作后发现密钥无法登录，您将可能会被永久锁定在服务器之外！${NC}
${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
    read -p "您是否已经测试并确认密钥可以登录，并希望继续禁用密码登录？请输入 'yes' 以确认: " final_confirmation

    if [ "$final_confirmation" != "yes" ]; then
        echo -e "${YELLOW}操作已取消。密码登录保持启用状态。${NC}"
        return
    fi

    echo -e "${YELLOW}正在执行禁用密码登录...${NC}"
    sudo cp "$sshd_config" "${sshd_config}.bak.$(date +%F)"
    echo "已备份 sshd_config 文件到 ${sshd_config}.bak.$(date +%F)"

    sudo sed -i -E 's/^[#\s]*PasswordAuthentication\s+(yes|no)/PasswordAuthentication no/' "$sshd_config"
    sudo sed -i -E 's/^[#\s]*ChallengeResponseAuthentication\s+(yes|no)/ChallengeResponseAuthentication no/' "$sshd_config"
    echo -e "${GREEN}✓ 配置文件 /etc/ssh/sshd_config 已更新。${NC}"

    echo "正在尝试重启 SSH 服务..."
    if command -v systemctl &> /dev/null; then
        sudo systemctl restart sshd
    elif command -v service &> /dev/null; then
        sudo service ssh restart
    else
        echo -e "${RED}无法确定如何重启 SSH 服务。请手动重启。${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ SSH 服务已成功重启。密码登录现已禁用。${NC}"
}


# --- 主逻辑 ---
main() {
    # ... 参数解析部分不变 ...
    local comment=""
    local passphrase=""
    local auto_disable_pw=false
    local interactive_mode=true
    if [ "$#" -gt 0 ]; then interactive_mode=false; fi
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

    # 脚本开始时执行检测
    get_public_ips
    detect_environment
    ensure_ssh_dir

    local key_path
    local backup_dir="$HOME/ed25519_$(date +%Y-%m-%d)"
    mkdir -p "$backup_dir"
    key_path="$backup_dir/id_ed25519"

    # --- 交互模式 ---
    if [ "$interactive_mode" = true ]; then
        # ... 生成密钥或粘贴密钥的逻辑基本不变，但后续处理会根据环境变化 ...
        read -p "默认将为您生成新密钥。是否要改为手动粘贴一个公钥? (y/N): " choice
        if [[ "$choice" =~ ^[yY是]$ ]]; then
            echo "请粘贴您的公钥内容，然后按 Ctrl + D 结束输入:"
            local temp_pub_key
            temp_pub_key=$(cat)
            
            if [ "$ENVIRONMENT" = "cloud" ]; then
                echo -e "\n${YELLOW}警告：检测到云平台环境，建议通过官方控制台管理密钥。${NC}"
                echo -e "${RED}脚本未自动修改 authorized_keys 文件。${NC}"
                echo "您粘贴的公钥是:"
                echo -e "${GREEN}$temp_pub_key${NC}"
            else
                echo "$temp_pub_key" >> "$HOME/.ssh/authorized_keys"
                sort -u "$HOME/.ssh/authorized_keys" -o "$HOME/.ssh/authorized_keys"
                echo -e "${GREEN}✓ 提供的公钥已添加到 ~/.ssh/authorized_keys。${NC}"
            fi
        else
            read -p "请输入密钥注释 (例如 your_email@example.com): " comment
            comment=${comment:-$(whoami)@$(hostname)}
            read -s -p "请输入可选的密钥密码 (留空则无密码): " passphrase
            echo; read -s -p "请再次输入密码以确认: " passphrase2; echo
            if [ "$passphrase" != "$passphrase2" ]; then echo -e "${RED}密码不匹配。已中止。${NC}"; exit 1; fi

            echo -e "${YELLOW}正在生成 ED25519 密钥对...${NC}"
            ssh-keygen -t ed25519 -C "$comment" -N "$passphrase" -f "$key_path"

            if [ $? -ne 0 ]; then echo -e "${RED}密钥生成失败。${NC}"; exit 1; fi
            
            echo -e "${GREEN}✓ 密钥对已成功生成。${NC}"
            if [ "$ENVIRONMENT" = "cloud" ]; then
                echo -e "\n${YELLOW}检测到云平台环境！${NC}"
                echo -e "为避免配置被覆盖，脚本${RED}未自动修改${NC} authorized_keys 文件。"
                echo -e "请将下面的 ${GREEN}公钥内容${NC} 复制并添加到您的云平台控制台（例如 GCP 的 '元数据 -> SSH 密钥'）。"
                echo "------------------------- 公钥 START -------------------------"
                cat "${key_path}.pub"
                echo "-------------------------- 公钥 END --------------------------"
            else
                cat "${key_path}.pub" >> "$HOME/.ssh/authorized_keys"
                echo -e "${GREEN}✓ 公钥已自动添加到 ~/.ssh/authorized_keys。${NC}"
            fi
            echo -e "${YELLOW}重要: 您的私钥已保存到: ${key_path}${NC}"
            echo -e "${YELLOW}请务必妥善备份此私钥文件！${NC}"
        fi

        # 根据环境判断是否询问禁用密码登录
        if [ "$ENVIRONMENT" = "shared_host" ]; then
            echo -e "\n${YELLOW}检测到共享主机环境，通常不允许修改 SSHD 配置。已跳过“禁用密码登录”步骤。${NC}"
        elif [ "$ENVIRONMENT" = "cloud" ]; then
             echo -e "\n${YELLOW}在云平台环境中，建议通过平台的防火墙和安全组规则管理访问，而不是直接修改 SSHD 配置。已跳过此步骤。${NC}"
        else
            read -p "配置完成。是否要禁用服务器的密码登录？ (y/N): " disable_choice
            if [[ "$disable_choice" =~ ^[yY是]$ ]]; then
                disable_password_login
            else
                echo "已跳过禁用密码登录。您仍然可以使用密码登录。"
            fi
        fi

    # --- 非交互模式 ---
    else
        echo "运行在非交互模式..."
        if [ "$ENVIRONMENT" = "cloud" ]; then
             echo -e "${RED}错误：在云平台环境中，非交互式修改 authorized_keys 和 sshd_config 风险很高。请使用交互模式。操作中止。${NC}"
             exit 1
        fi
        # ... (非交互式生成密钥的逻辑不变) ...
        if [ -z "$comment" ]; then comment="$(whoami)@$(hostname)"; fi
        ssh-keygen -t ed25519 -C "$comment" -N "$passphrase" -f "$key_path"
        if [ $? -ne 0 ]; then echo -e "${RED}密钥生成失败。${NC}"; exit 1; fi
        cat "${key_path}.pub" >> "$HOME/.ssh/authorized_keys"
        echo -e "${GREEN}✓ 公钥已添加到 ~/.ssh/authorized_keys。${NC}"
        echo -e "${YELLOW}重要: 私钥已保存到: ${key_path}${NC}"
        
        if [ "$auto_disable_pw" = true ]; then
            if [ "$ENVIRONMENT" = "shared_host" ]; then
                echo -e "${YELLOW}警告: 在共享主机环境检测到 '-y' 参数，但此操作被禁止。跳过禁用密码登录。${NC}"
            else
                disable_password_login # 注意：非交互模式下，此函数依然会要求最终确认
            fi
        fi
    fi

    echo -e "\n${GREEN}===== 所有操作已完成 =====${NC}"
    echo -e "本机公网 IPv4 地址: ${YELLOW}${PUBLIC_IPV4}${NC}"
    echo -e "本机公网 IPv6 地址: ${YELLOW}${PUBLIC_IPV6}${NC}"
    if [ "$ENVIRONMENT" = "shared_host" ]; then
        echo -e "${YELLOW}警告: 在共享主机上，以上 IP 可能是共享 IP，请与服务商确认您的 SSH 连接地址。${NC}"
    fi
    echo -e "登录命令示例: ${YELLOW}ssh -i /path/to/your/private_key $(whoami)@${PUBLIC_IPV4:-'your_server_ip'}${NC}"
}

# 脚本入口
main "$@"
