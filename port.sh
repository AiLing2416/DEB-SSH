#!/bin/bash

# DEB-SSH Port Script
# 配置SSH端口

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}需要sudo权限.${NC}"
    exit 1
fi

if [ -n "$1" ]; then
    PORT="$1"
else
    echo -e "${GREEN}进入交互模式: 输入端口号 (默认22)${NC}"
    read PORT
    PORT=${PORT:-22}
fi

if [[ ! "$PORT" =~ ^[0-9]+$ || "$PORT" -lt 1 || "$PORT" -gt 65535 ]]; then
    echo -e "${RED}无效端口.${NC}"
    exit 1
fi

echo -e "${RED}警告：更改端口后，请勿立即关闭当前连接！先用新端口测试SSH连接成功后再关闭旧会话。${NC}"

sed -i "s/^#Port .*/Port $PORT/" /etc/ssh/sshd_config
sed -i "s/^Port .*/Port $PORT/" /etc/ssh/sshd_config

if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT"/tcp
    ufw reload
    echo -e "${GREEN}UFW更新.${NC}"
fi

systemctl restart ssh
echo -e "${GREEN}端口设置为 $PORT.${NC}"
