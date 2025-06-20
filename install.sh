#!/bin/bash

# ==============================================================================
# DEB-SSH 工具集安装与卸载脚本
# 作者: Gemini
# 版本: 1.0
# ==============================================================================

# --- 配置区 ---

# 脚本源 URL
BASE_URL="https://raw.githubusercontent.com/AiLing2416/DEB-SSH/main"

# 目标机工具集
TARGET_SCRIPTS=(
    "keys.sh|dsh-k"
    "port.sh|dsh-p"
)

# 跳板机工具集
JUMP_HOST_SCRIPTS=(
    "target-manager.sh|tm"
    "c.sh|c"
)

# 安装路径 (系统级指令)
INSTALL_DIR="/usr/local/bin"

# 跳板机脚本的存放路径 (用户家目录)
JUMP_HOST_CONFIG_DIR_NAME=".ssh_targets"

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- 辅助函数 ---

# 检查是否以 root 身份运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本需要以 root 权限运行。请使用 'sudo bash $0'。${NC}"
        exit 1
    fi
}

# 获取真实用户的家目录 (即使在 sudo下也能工作)
get_user_home() {
    if [ -n "$SUDO_USER" ]; then
        echo "/home/$SUDO_USER"
    else
        # 如果直接以root登录，则可能是/root
        echo "$HOME"
    fi
}

# --- 核心功能函数 ---

install_target_tools() {
    echo -e "\n${YELLOW}>>> 正在安装目标机工具集...${NC}"
    for script_info in "${TARGET_SCRIPTS[@]}"; do
        IFS='|' read -r SCRIPT_NAME CMD_NAME <<< "$script_info"
        echo -n "  - 正在安装 ${CMD_NAME}... "
        curl -sSL "${BASE_URL}/${SCRIPT_NAME}" -o "${INSTALL_DIR}/${CMD_NAME}"
        if [ $? -eq 0 ]; then
            chmod +x "${INSTALL_DIR}/${CMD_NAME}"
            echo -e "${GREEN}[成功]${NC}"
        else
            echo -e "${RED}[失败] - 下载文件时出错。${NC}"
        fi
    done
}

install_jump_host_tools() {
    echo -e "\n${YELLOW}>>> 正在安装跳板机工具集...${NC}"
    local USER_HOME=$(get_user_home)
    local JUMP_HOST_BASE_DIR="${USER_HOME}/${JUMP_HOST_CONFIG_DIR_NAME}"
    local JUMP_HOST_SCRIPT_DIR="${JUMP_HOST_BASE_DIR}/scripts"
    
    # 1. 创建目录结构
    echo "  - 正在创建配置目录: ${JUMP_HOST_BASE_DIR}"
    mkdir -p "${JUMP_HOST_BASE_DIR}/keys"
    mkdir -p "${JUMP_HOST_SCRIPT_DIR}"
    chown -R "$SUDO_USER:$SUDO_USER" "$JUMP_HOST_BASE_DIR" 2>/dev/null

    # 2. 下载脚本
    for script_info in "${JUMP_HOST_SCRIPTS[@]}"; do
        IFS='|' read -r SCRIPT_NAME CMD_NAME <<< "$script_info"
        echo -n "  - 正在下载 ${SCRIPT_NAME}... "
        curl -sSL "${BASE_URL}/${SCRIPT_NAME}" -o "${JUMP_HOST_SCRIPT_DIR}/${SCRIPT_NAME}"
        if [ $? -eq 0 ]; then
            chmod +x "${JUMP_HOST_SCRIPT_DIR}/${SCRIPT_NAME}"
            echo -e "${GREEN}[成功]${NC}"
        else
            echo -e "${RED}[失败] - 下载文件时出错。${NC}"
        fi
    done
    
    # 3. 配置别名
    echo "  - 正在配置 Shell 别名..."
    local SHELL_CONFIG_FILE=""
    if [ -f "${USER_HOME}/.zshrc" ]; then
        SHELL_CONFIG_FILE="${USER_HOME}/.zshrc"
    elif [ -f "${USER_HOME}/.bashrc" ]; then
        SHELL_CONFIG_FILE="${USER_HOME}/.bashrc"
    else
        echo -e "  ${YELLOW}警告: 找不到 .bashrc 或 .zshrc 文件。请手动配置别名。${NC}"
        return
    fi

    # 别名配置块，方便卸载
    ALIAS_BLOCK="
# --- DEB-SSH Aliases ---
alias tm=\"bash ${JUMP_HOST_SCRIPT_DIR}/target-manager.sh\"
alias c=\"bash ${JUMP_HOST_SCRIPT_DIR}/c.sh\"
# --- End DEB-SSH Aliases ---
"
    # 检查是否已存在，不存在则添加
    if ! grep -q "# --- DEB-SSH Aliases ---" "$SHELL_CONFIG_FILE"; then
        echo "$ALIAS_BLOCK" >> "$SHELL_CONFIG_FILE"
        echo -e "  ${GREEN}别名已成功添加到 ${SHELL_CONFIG_FILE}${NC}"
    else
        echo -e "  ${YELLOW}别名已存在，跳过添加。${NC}"
    fi
}

uninstall_all() {
    echo -e "\n${YELLOW}>>> 正在卸载 DEB-SSH 工具集...${NC}"
    local USER_HOME=$(get_user_home)

    # 1. 移除系统级指令
    echo "  - 正在移除目标机指令..."
    for script_info in "${TARGET_SCRIPTS[@]}"; do
        IFS='|' read -r _ CMD_NAME <<< "$script_info"
        rm -f "${INSTALL_DIR}/${CMD_NAME}"
    done

    # 2. 移除 Shell 别名
    echo "  - 正在移除 Shell 别名..."
    for config_file in "${USER_HOME}/.bashrc" "${USER_HOME}/.zshrc"; do
        if [ -f "$config_file" ]; then
            # 使用sed删除别名块，并创建备份
            sed -i.bak '/# --- DEB-SSH Aliases ---/,/# --- End DEB-SSH Aliases ---/d' "$config_file"
        fi
    done

    # 3. 询问是否移除配置文件和目录
    echo ""
    read -p "$(echo -e ${YELLOW}"是否要彻底移除跳板机配置文件和私钥目录 (~/${JUMP_HOST_CONFIG_DIR_NAME})？这是一个危险操作！[y/N]: "${NC})" CONFIRM
    
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "  - 正在移除配置目录: ${USER_HOME}/${JUMP_HOST_CONFIG_DIR_NAME}"
        rm -rf "${USER_HOME}/${JUMP_HOST_CONFIG_DIR_NAME}"
        echo -e "  ${GREEN}配置目录已移除。${NC}"
    else
        echo "  - 保留了配置目录。"
    fi
    
    echo -e "\n${GREEN}卸载完成！${NC}"
    echo "请运行 'source ~/.bashrc' 或 'source ~/.zshrc'，或重新打开终端以使更改完全生效。"
}

display_main_menu() {
    clear
    echo "=========================================="
    echo "    DEB-SSH 工具集 安装程序"
    echo "=========================================="
    echo "请选择要安装的组件："
    echo ""
    echo "  1) 目标机工具集 (dsh-k, dsh-p)"
    echo "     (用于创建密钥、修改端口等基础操作)"
    echo ""
    echo "  2) 跳板机工具集 (tm, c)"
    echo "     (用于管理和连接多个远程服务器)"
    echo ""
    echo "  3) 全部安装"
    echo ""
    echo "  q) 退出"
    echo "=========================================="
    read -p "请输入您的选择 [1-3, q]: " choice
    
    case "$choice" in
        1)
            install_target_tools
            ;;
        2)
            install_jump_host_tools
            ;;
        3)
            install_target_tools
            install_jump_host_tools
            ;;
        q)
            echo "安装已取消。"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重试。${NC}"
            sleep 1
            display_main_menu
            ;;
    esac
}

# --- 脚本主入口 ---

# 检查是否为卸载模式
if [ "$1" == "-del" ] || [ "$1" == "--uninstall" ]; then
    check_root
    uninstall_all
    exit 0
fi

# 正常安装模式
check_root
display_main_menu

echo -e "\n${GREEN}🎉 安装完成！${NC}"
echo "请运行 'source ~/.bashrc' 或 'source ~/.zshrc'，或重新打开一个终端来使用新命令。"
echo ""
