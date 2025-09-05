#!/bin/bash

# DEB-SSH Install Script
# 快速安装OpenSSH服务器

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}开始安装 DEB-SSH...${NC}"

if ! grep -iqE 'debian|ubuntu' /etc/os-release; then
    echo -e "${RED}错误: 仅支持Debian/Ubuntu.${NC}"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}需要sudo权限运行.${NC}"
    exit 1
fi

if ! command -v sshd >/dev/null 2>&1; then
    apt update -y
    apt install openssh-server -y
    systemctl enable ssh
    systemctl start ssh
    echo -e "${GREEN}SSH服务器安装完成!${NC}"
else
    echo -e "${GREEN}SSH已安装.${NC}"
fi
