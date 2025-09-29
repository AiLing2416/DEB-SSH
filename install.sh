#!/bin/bash

# --- 变量定义 ---
readonly GITHUB_REPO="AiLing2416/DEB-SSH"
readonly SCRIPT_NAME="sshm.sh"
readonly TARGET_COMMAND="sshm"

# --- 颜色定义 ---
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_CYAN='\033[0;36m'

# --- 主安装逻辑 ---
main() {
    # 目标安装路径
    local install_dir="$HOME/.local/bin"
    local install_path="$install_dir/$TARGET_COMMAND"
    local source_url="https://raw.githubusercontent.com/$GITHUB_REPO/main/$SCRIPT_NAME"

    echo -e "${C_CYAN}--- 开始安装 sshm 主机管理工具 ---${C_RESET}"

    # 1. 确保目标目录存在
    echo "正在准备安装目录: $install_dir"
    mkdir -p "$install_dir"

    # 2. 检查 PATH 环境变量
    # 这是一个非常重要的用户体验环节
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        echo -e "\n${C_YELLOW}警告: 您的安装目录 '$install_dir' 当前不在 PATH 环境变量中。${C_RESET}"
        echo "为了能直接运行 'sshm' 命令，您需要将此目录添加到 PATH。"
        echo "请将以下命令添加到您的 shell 配置文件 (例如 ~/.bashrc 或 ~/.zshrc) 中:"
        echo -e "${C_GREEN}export PATH=\"\$HOME/.local/bin:\$PATH\"${C_RESET}"
        echo "添加后，请重启您的终端或运行 'source ~/.bashrc' 来使更改生效。"
        echo # 空行以示分隔
    fi

    # 3. 从 GitHub 下载最新的脚本
    echo "正在从 GitHub 下载最新的 '$SCRIPT_NAME'..."
    if curl -sSL -o "$install_path" "$source_url"; then
        echo -e "${C_GREEN}✓ 下载成功。${C_RESET}"
    else
        echo -e "${C_RED}✗ 下载失败。请检查您的网络连接或确认 URL 是否正确: $source_url${C_RESET}"
        exit 1
    fi

    # 4. 赋予执行权限
    echo "正在为脚本设置执行权限..."
    chmod +x "$install_path"
    if [ $? -eq 0 ]; then
        echo -e "${C_GREEN}✓ 权限设置成功。${C_RESET}"
    else
        echo -e "${C_RED}✗ 权限设置失败。${C_RESET}"
        exit 1
    fi

    # 5. 完成提示
    echo -e "\n${C_GREEN}===== 'sshm' 安装完成! =====${C_RESET}"
    echo "已安装到: ${C_YELLOW}$install_path${C_RESET}"
    echo "现在您可以直接在终端中使用 ${C_GREEN}sshm${C_RESET} 命令了。"
    echo "运行 ${C_YELLOW}'sshm -h'${C_RESET} 来查看所有可用选项。"
}

# 脚本入口
main
