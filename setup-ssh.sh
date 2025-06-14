#!/bin/bash

# ===================================================================================
# Final SSH Key Generation, Setup, and Check Script for Debian-based Systems
# Author: Gemini
# Version: 3.0
# Features:
#   - Dependency check with auto-install
#   - User choice for enabling/disabling passphrase
#   - Random password generation if passphrase is enabled but left blank
#   - Fixed all color output rendering issues
# ===================================================================================

# 设置颜色变量以便输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 函数：依赖检查与安装 ---
check_and_install_dependencies() {
    local missing_deps=()
    echo -e "${BLUE}1. 正在检查所需依赖...${NC}"

    if ! command -v ssh-keygen &> /dev/null; then missing_deps+=("openssh-client"); fi
    if ! command -v openssl &> /dev/null; then missing_deps+=("openssl"); fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}警告：缺少以下必要依赖: ${missing_deps[*]}.${NC}"
        read -p "是否尝试使用 'sudo apt-get install' 自动安装? (y/N): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}"
            if [ $? -ne 0 ]; then echo -e "${RED}依赖安装失败！请手动安装后重试。${NC}"; exit 1; fi
            echo -e "${GREEN}依赖已成功安装！${NC}"
        else
            echo -e "${RED}用户取消。请先手动安装 ${missing_deps[*]} 后再运行此脚本。${NC}"; exit 1
        fi
    else
        echo -e "${GREEN}✅ 所有依赖均已满足。${NC}"
    fi
}

# --- 主脚本逻辑 ---

# 步骤 1: 运行依赖检查
check_and_install_dependencies
echo "-----------------------------------------------------"

# 步骤 2: 获取用户信息与配置密码
echo -e "${BLUE}2. 正在配置 SSH 密钥...${NC}"
CURRENT_USER=$(whoami)
HOSTNAME=$(hostname)
DEFAULT_COMMENT="${CURRENT_USER}@${HOSTNAME}-$(date +%Y%m%d)"
PASSPHRASE=""
RANDOM_PASS_GENERATED=false

echo "密钥将使用目前最安全的 Ed25519 算法生成。"
read -p "请输入密钥的注释 (直接回车将使用默认值: ${DEFAULT_COMMENT}): " KEY_COMMENT
KEY_COMMENT=${KEY_COMMENT:-$DEFAULT_COMMENT}

# 新增：询问用户是否要添加密码
echo
echo -e "${YELLOW}说明：${NC}为私钥添加密码是一个非常重要的安全措施。"
echo -e "它能确保即使您的私钥文件（id_ed25519）被盗，黑客没有密码也无法使用它。"
read -p "是否为您的私钥添加密码保护? [Y/n]: " use_passphrase
echo

# 根据用户选择处理密码
if [[ "$use_passphrase" =~ ^[nN]$ ]]; then
    # 用户选择不使用密码
    PASSPHRASE=""
    echo -e "${YELLOW}您选择不设置密码。请务必保证私钥文件的绝对安全！${NC}"
else
    # 用户选择使用密码（默认选项）
    read -s -p "请输入一个强密码来保护你的私钥 (留空则自动生成): " PASSPHRASE
    echo
    if [ -z "$PASSPHRASE" ]; then
        # 留空，自动生成随机密码
        PASSPHRASE=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)
        RANDOM_PASS_GENERATED=true
        echo -e "${YELLOW}您未设置密码，已为您生成一个随机密码: ${GREEN}${PASSPHRASE}${NC}"
        echo -e "${YELLOW}请务必记下此密码！${NC}"
    else
        # 手动输入密码，要求确认
        read -s -p "请再次输入密码以确认: " PASSPHRASE_CONFIRM
        echo
        if [ "$PASSPHRASE" != "$PASSPHRASE_CONFIRM" ]; then
            echo -e "${RED}两次输入的密码不匹配，脚本终止。${NC}"; exit 1
        fi
        echo -e "${GREEN}密码设置成功。${NC}"
    fi
fi

# 步骤 3: 密钥生成与配置
echo -e "\n${BLUE}3. 正在执行密钥生成与服务器配置...${NC}"
SSH_DIR="$HOME/.ssh"
KEY_NAME="id_ed25519"
PRIVATE_KEY_PATH="${SSH_DIR}/${KEY_NAME}"
PUBLIC_KEY_PATH="${SSH_DIR}/${KEY_NAME}.pub"
AUTHORIZED_KEYS_PATH="${SSH_DIR}/authorized_keys"

# 创建 .ssh 目录并设置权限
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
echo "✅ 权限已确认/设置为 700 for ${SSH_DIR}"

# 生成 SSH 密钥对
echo "正在生成 Ed25519 密钥对..."
ssh-keygen -t ed25519 -C "$KEY_COMMENT" -f "$PRIVATE_KEY_PATH" -N "$PASSPHRASE" -q

if [ $? -ne 0 ]; then echo -e "${RED}密钥生成失败！${NC}"; exit 1; fi

# 配置 authorized_keys
cat "$PUBLIC_KEY_PATH" >> "$AUTHORIZED_KEYS_PATH"
chmod 600 "$AUTHORIZED_KEYS_PATH"
echo "✅ 公钥已添加，权限已设置为 600 for ${AUTHORIZED_KEYS_PATH}"

# 准备供下载的私钥
DOWNLOAD_DIR="$HOME/new_ssh_private_key_$(date +%s)"
mkdir -p "$DOWNLOAD_DIR" && chmod 700 "$DOWNLOAD_DIR"
cp "$PRIVATE_KEY_PATH" "$DOWNLOAD_DIR/" && chmod 600 "${DOWNLOAD_DIR}/${KEY_NAME}"
echo "✅ 私钥已准备好供您下载。"

# 步骤 4: 显示最终的重要信息 (已修复所有 echo 输出)
echo -e "\n-----------------------------------------------------"
echo -e "${GREEN}✅✅✅ SSH 密钥配置成功！✅✅✅${NC}\n"
echo -e "${RED}!!!!!!!!!! 重要：请立即执行以下操作 !!!!!!!!!!!${NC}"

# 如果设置了密码，再次提醒
if [ -n "$PASSPHRASE" ]; then
    if [ "$RANDOM_PASS_GENERATED" = true ]; then
        echo -e "${YELLOW}🔑 您的随机生成的私钥密码是: ${GREEN}${PASSPHRASE}${NC}"
        echo -e "${YELLOW}   (这是您唯一一次看到此密码，请务必妥善保管！)${NC}\n"
    else
        echo -e "${GREEN}ℹ️ 请记住您为私钥设置的密码，登录时需要使用。${NC}\n"
    fi
fi

echo -e "1.  ${YELLOW}下载你的私钥${NC}：私钥已保存到服务器的以下目录中："
echo -e "    ${BLUE}${DOWNLOAD_DIR}/${KEY_NAME}${NC}"
echo -e "    请使用 scp 或 sftp 等工具将其下载到你的【本地电脑】。例如："
echo -e "    ${BLUE}scp ${CURRENT_USER}@<你的服务器IP>:${DOWNLOAD_DIR}/${KEY_NAME} ./${NC}"
echo

echo -e "2.  ${YELLOW}删除服务器上的私钥备份${NC}：下载完成后，请务必删除服务器上的这个临时目录："
echo -e "    ${BLUE}rm -rf ${DOWNLOAD_DIR}${NC}"
echo

echo -e "3.  ${YELLOW}测试登录${NC}：使用新密钥从你的本地电脑尝试登录服务器："
echo -e "    ${BLUE}ssh -i /path/to/your/downloaded/${KEY_NAME} ${CURRENT_USER}@<你的服务器IP>${NC}"
if [ -n "$PASSPHRASE" ]; then
    echo -e "    登录时会提示输入密码，请输入你刚才设置或脚本生成的那个【私钥密码】。"
else
    echo -e "    由于未设置私钥密码，应该可以直接登录，无需输入额外密码。"
fi
echo

echo -e "4.  ${YELLOW}禁用密码登录（最终安全步骤）${NC}："
echo -e "    确认密钥登录完全没问题后，编辑 ${YELLOW}/etc/ssh/sshd_config${NC} 文件，"
echo -e "    找到并修改 ${YELLOW}PasswordAuthentication yes${NC} 为 ${YELLOW}PasswordAuthentication no${NC}，"
echo -e "    然后重启 SSH 服务：${YELLOW}sudo systemctl restart sshd${NC}"
echo -e "-----------------------------------------------------"
