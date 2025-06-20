#!/bin/bash

# ==============================================================================
# Dedicated SSH Port Changer for Debian-based Systems
# Author: Gemini
# Version: 1.0
# Features: Root check, port validation, config backup, syntax check, UFW firewall integration
# ==============================================================================

# --- 颜色定义 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 1. 安全检查 ---
# 必须以 root 身份运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：此脚本需要以 root 权限运行。请使用 'sudo ./change_ssh_port.sh <端口号>'${NC}"
    exit 1
fi

# 检查是否提供了端口参数
if [ -z "$1" ]; then
    echo -e "${RED}错误：缺少参数。${NC}"
    echo "用法: sudo ./change_ssh_port.sh <新的SSH端口号>"
    exit 1
fi

# --- 2. 端口验证 ---
NEW_PORT=$1
# 正则表达式检查是否为纯数字
if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}错误：端口 '$NEW_PORT' 不是一个有效的数字。${NC}"
    exit 1
fi

# 检查端口范围
if [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
    echo -e "${RED}错误：端口号必须在 1-65535 之间。${NC}"
    exit 1
fi

if [ "$NEW_PORT" -lt 1024 ]; then
    echo -e "${YELLOW}警告：你选择了一个1024以下的熟知端口。这通常不被推荐，但脚本将继续执行。${NC}"
fi

echo -e "${BLUE}准备将 SSH 端口修改为: ${GREEN}$NEW_PORT${NC}"
echo "-----------------------------------------------------"

# --- 3. 核心操作 ---
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"

# a. 自动备份配置文件 (非常重要!)
BACKUP_FILE="/etc/ssh/sshd_config.bak.$(date +%F_%T)"
echo "正在备份当前配置文件到: $BACKUP_FILE ..."
cp "$SSHD_CONFIG_FILE" "$BACKUP_FILE"
if [ $? -ne 0 ]; then
    echo -e "${RED}错误：备份失败！操作已中止。${NC}"
    exit 1
fi
echo -e "${GREEN}✅ 备份成功。${NC}"

# b. 修改端口号 (使用 sed, 能处理已存在或被注释的 Port 行)
echo "正在修改配置文件中的端口号..."
# 先检查 Port 配置是否存在，不存在则在末尾添加
if ! grep -qE "^#?Port" "$SSHD_CONFIG_FILE"; then
    echo -e "\nPort $NEW_PORT" >> "$SSHD_CONFIG_FILE"
else
    # 如果存在，则替换它
    sed -i -E "s/^#?Port [0-9]+/Port $NEW_PORT/" "$SSHD_CONFIG_FILE"
fi
echo -e "${GREEN}✅ 配置文件修改完成。${NC}"


# c. 检查新配置文件的语法 (非常重要!)
echo "正在检查新配置文件的语法..."
sshd -t
if [ $? -ne 0 ]; then
    echo -e "${RED}错误：新的SSH配置文件语法不正确！${NC}"
    echo "正在从备份 $BACKUP_FILE 自动恢复..."
    cp "$BACKUP_FILE" "$SSHD_CONFIG_FILE"
    echo -e "${GREEN}✅ 配置文件已恢复。服务器很安全，操作已中止。${NC}"
    exit 1
fi
echo -e "${GREEN}✅ 语法检查通过。${NC}"

# d. 配置防火墙 (UFW)
if command -v ufw &> /dev/null && ufw status | grep -q 'Status: active'; then
    echo "检测到 UFW 防火墙处于活动状态，正在配置..."
    ufw allow "$NEW_PORT/tcp"
    echo -e "${GREEN}✅ 防火墙规则已添加：允许端口 $NEW_PORT/tcp。${NC}"
else
    echo -e "${YELLOW}警告：未检测到活动的 UFW 防火墙。请确保你使用的防火墙（如iptables, firewalld）已手动放行端口 $NEW_PORT/tcp。${NC}"
fi

# e. 重启 SSH 服务
echo "正在重启 SSH 服务以应用新配置..."
systemctl restart sshd
echo -e "${GREEN}✅ SSH 服务已重启。${NC}"

# --- 4. 最终提示 ---
echo "-----------------------------------------------------"
echo -e "${GREEN}🎉 成功！SSH 端口已修改为 ${YELLOW}$NEW_PORT${NC}。${NC}"
echo
echo -e "${RED}!!!!!!!!!! 极其重要的后续步骤 !!!!!!!!!!!${NC}"
echo -e "1. ${YELLOW}请不要关闭当前这个终端窗口！${NC} 这是一个安全绳。"
echo -e "2. ${YELLOW}请打开一个新的终端窗口${NC}，并使用以下命令尝试连接你的服务器："
echo -e "   ${BLUE}ssh ${USER}@<你的服务器IP> -p ${NEW_PORT}${NC}"
echo
echo -e "3. ${GREEN}如果新连接成功${NC}，恭喜你！你可以安全地关闭这个旧的终端窗口了。"
echo
echo -e "4. ${RED}如果新连接失败${NC}，请回到这个旧窗口，执行以下命令进行恢复："
echo -e "   ${BLUE}sudo cp ${BACKUP_FILE} ${SSHD_CONFIG_FILE} && sudo systemctl restart sshd${NC}"
echo -e "   这会将一切恢复到修改之前的状态，你可以用旧端口重新登录。"
echo "-----------------------------------------------------"
