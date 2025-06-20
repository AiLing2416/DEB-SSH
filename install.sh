#!/bin/bash

# ==============================================================================
# DEB-SSH 工具集安装与卸载脚本
# 作者: Gemini (根据 AiLing2416 的需求创建)
# 版本: 2.1 (修正卸载提示中的引号错误)
# ==============================================================================

# --- 配置区 ---
BASE_URL="https://raw.githubusercontent.com/AiLing2416/DEB-SSH/main"
TARGET_SCRIPTS=("keys.sh|dsh-k" "port.sh|dsh-p")
JUMP_HOST_SCRIPTS=("target-manager.sh|tm" "c.sh|c")
INSTALL_DIR="/usr/local/bin"
JUMP_HOST_CONFIG_DIR_NAME=".ssh_targets"

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- 辅助函数 ---

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本需要以 root 权限运行。请使用 'sudo bash $0'。${NC}"
        exit 1
    fi
}

get_user_home() {
    # 即使在 sudo 下也能工作
    echo "${SUDO_USER_HOME:-$HOME}"
}

# --- 依赖检测与安装函数 ---
check_and_install_dependencies() {
    echo -e "${YELLOW}>>> 正在检查脚本依赖...${NC}"
    
    local MISSING_PKGS=()
    # 定义命令和对应包的映射
    declare -A CMD_TO_PKG
    CMD_TO_PKG["column"]="bsdmainutils"
    CMD_TO_PKG["curl"]="curl"
    CMD_TO_PKG["ssh-keygen"]="openssh-client"

    for cmd in "${!CMD_TO_PKG[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "  - ${YELLOW}检测到命令缺失: ${cmd}${NC}"
            MISSING_PKGS+=("${CMD_TO_PKG[$cmd]}")
        fi
    done

    if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
        echo -e "  ${GREEN}所有依赖均已满足。${NC}"
        return
    fi

    echo -e "\n${YELLOW}以下必需的软件包缺失: ${MISSING_PKGS[*]}.${NC}"
    read -p "是否要尝试自动安装它们？[Y/n]: " choice
    choice=${choice:-Y} # 默认为 Y

    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${RED}用户取消，退出安装。${NC}"
        exit 1
    fi

    # 检测包管理器并安装
    if command -v apt-get &> /dev/null; then
        echo "  - 正在使用 apt 更新软件包列表..."
        apt-get update -qq
        echo "  - 正在安装依赖包: ${MISSING_PKGS[*]}"
        apt-get install -y "${MISSING_PKGS[@]}"
    elif command -v dnf &> /dev/null; then
        echo "  - 正在使用 dnf 安装依赖包: ${MISSING_PKGS[*]}"
        dnf install -y "${MISSING_PKGS[@]}"
    elif command -v yum &> /dev/null; then
        echo "  - 正在使用 yum 安装依赖包: ${MISSING_PKGS[*]}"
        yum install -y "${MISSING_PKGS[@]}"
    else
        echo -e "${RED}错误: 无法识别您的操作系统包管理器 (apt/dnf/yum)。${NC}"
        echo -e "${RED}请手动安装以下软件包后重试: ${MISSING_PKGS[*]}${NC}"
        exit 1
    fi

    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 依赖安装失败。请检查您的网络连接和包管理器配置。${NC}"
        exit 1
    fi

    echo -e "${GREEN}依赖已成功安装！${NC}"
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
    # SUDO_USER_HOME 变量在脚本开始时设置，确保一致性
    local JUMP_HOST_BASE_DIR="${SUDO_USER_HOME}/${JUMP_HOST_CONFIG_DIR_NAME}"
    local JUMP_HOST_SCRIPT_DIR="${JUMP_HOST_BASE_DIR}/scripts"
    
    echo "  - 正在创建配置目录: ${JUMP_HOST_BASE_DIR}"
    mkdir -p "${JUMP_HOST_BASE_DIR}/keys"
    mkdir -p "${JUMP_HOST_SCRIPT_DIR}"
    # 如果SUDO_USER存在，则chown
    [ -n "$SUDO_USER" ] && chown -R "$SUDO_USER:$SUDO_USER" "$JUMP_HOST_BASE_DIR"

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
    
    echo "  - 正在配置 Shell 别名..."
    local SHELL_CONFIG_FILE=""
    if [ -f "${SUDO_USER_HOME}/.zshrc" ]; then
        SHELL_CONFIG_FILE="${SUDO_USER_HOME}/.zshrc"
    elif [ -f "${SUDO_USER_HOME}/.bashrc" ]; then
        SHELL_CONFIG_FILE="${SUDO_USER_HOME}/.bashrc"
    else
        echo -e "  ${YELLOW}警告: 找不到 .bashrc 或 .zshrc 文件。请手动配置别名。${NC}"
        return
    fi

    ALIAS_BLOCK="\n# --- DEB-SSH Aliases ---\nalias tm=\"bash ${JUMP_HOST_SCRIPT_DIR}/target-manager.sh\"\nalias c=\"bash ${JUMP_HOST_SCRIPT_DIR}/c.sh\"\n# --- End DEB-SSH Aliases ---\n"
    if ! grep -q "# --- DEB-SSH Aliases ---" "$SHELL_CONFIG_FILE"; then
        echo -e "$ALIAS_BLOCK" >> "$SHELL_CONFIG_FILE"
        echo -e "  ${GREEN}别名已成功添加到 ${SHELL_CONFIG_FILE}${NC}"
    else
        echo -e "  ${YELLOW}别名已存在，跳过添加。${NC}"
    fi
}

uninstall_all() {
    echo -e "\n${YELLOW}>>> 正在卸载 DEB-SSH 工具集...${NC}"

    echo "  - 正在移除目标机指令..."
    for script_info in "${TARGET_SCRIPTS[@]}"; do
        IFS='|' read -r _ CMD_NAME <<< "$script_info"
        rm -f "${INSTALL_DIR}/${CMD_NAME}"
    done

    echo "  - 正在移除 Shell 别名..."
    for config_file in "${SUDO_USER_HOME}/.bashrc" "${SUDO_USER_HOME}/.zshrc"; do
        if [ -f "$config_file" ]; then
            sed -i.bak '/# --- DEB-SSH Aliases ---/,/# --- End DEB-SSH Aliases ---/d' "$config_file"
        fi
    done

    echo ""
    # --- 已修正的部分 ---
    # 先用 echo -e 打印带颜色的提示，然后用 read 读取输入
    # 这样避免了在 read -p 中复杂的引号嵌套问题
    echo -e -n "${YELLOW}是否要彻底移除跳板机配置文件和私钥目录 (~/${JUMP_HOST_CONFIG_DIR_NAME})？这是一个危险操作！[y/N]: ${NC}"
    read CONFIRM
    # --- 修正结束 ---
    
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "  - 正在移除配置目录: ${SUDO_USER_HOME}/${JUMP_HOST_CONFIG_DIR_NAME}"
        rm -rf "${SUDO_USER_HOME}/${JUMP_HOST_CONFIG_DIR_NAME}"
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
    echo "    DEB-SSH 工具集 安装程序 (v2.1)"
    echo "=========================================="
    echo "请选择要安装的组件："
    echo "  1) 目标机工具集 (dsh-k, dsh-p)"
    echo "  2) 跳板机工具集 (tm, c)"
    echo "  3) 全部安装"
    echo "  q) 退出"
    echo "=========================================="
    read -p "请输入您的选择 [1-3, q]: " choice
    
    case "$choice" in
        1) install_target_tools ;;
        2) install_jump_host_tools ;;
        3) install_target_tools; install_jump_host_tools ;;
        q) echo "安装已取消。"; exit 0 ;;
        *) echo -e "${RED}无效选择，请重试。${NC}"; sleep 1; display_main_menu ;;
    esac
}

# --- 脚本主入口 ---

# 优先处理 sudo 用户的家目录
if [ -n "$SUDO_USER" ]; then
    SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    SUDO_USER_HOME=$HOME
fi

# 检查卸载模式
if [ "$1" == "-del"
