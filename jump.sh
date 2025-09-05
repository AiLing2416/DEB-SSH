#!/bin/bash

# DEB-SSH Jump Script
# 配置跳板机 (添加到~/.ssh/config)

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

mkdir -p ~/.ssh
touch ~/.ssh/config
chmod 600 ~/.ssh/config

if [ "$1" = "add" ]; then
    if [ -n "$2" ]; then
        HOST="$2"
        PORT="${3:-22}"
        USER="${4:-$USER}"
        KEY="${5:-~/.ssh/id_rsa}"
    else
        echo -e "${GREEN}交互模式: 输入跳板主机${NC}"
        read HOST
        echo "端口 (默认22):"
        read PORT
        PORT=${PORT:-22}
        echo "用户 (默认$USER):"
        read USER
        USER=${USER:-$USER}
        echo "私钥路径 (默认~/.ssh/id_rsa):"
        read KEY
        KEY=${KEY:-~/.ssh/id_rsa}
    fi
    
    {
        echo ""
        echo "Host $HOST"
        echo "  HostName $HOST"
        echo "  Port $PORT"
        echo "  User $USER"
        echo "  IdentityFile $KEY"
    } >> ~/.ssh/config
    echo -e "${GREEN}跳板 $HOST 添加完成!${NC}"
elif [ "$1" = "list" ]; then
    grep '^Host ' ~/.ssh/config || echo -e "${RED}无跳板配置.${NC}"
else
    echo -e "${RED}用法: jump.sh add [host] [port] [user] [key] 或 jump.sh list${NC}"
    echo "无参数时交互添加."
    exit 1
fi
