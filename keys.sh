#!/bin/bash

# DEB-SSH Keys Script
# 为当前用户配置公钥/生成私钥

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

mkdir -p ~/.ssh
chmod 700 ~/.ssh

if [ "$1" = "generate" ]; then
    # 生成私钥
    if [ "$2" = "--random" ]; then
        RAND_DIR=$(mktemp -d /tmp/ssh_key_XXXXXX)
        echo -e "${GREEN}私钥将存储在随机目录: $RAND_DIR (不安全，仅测试用)${NC}"
        ssh-keygen -t rsa -b 4096 -f "$RAND_DIR/id_rsa" -N ""
        chmod 600 "$RAND_DIR/id_rsa"
        echo -e "${GREEN}私钥生成完成! 公钥: $(cat "$RAND_DIR/id_rsa.pub")${NC}"
    else
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        echo -e "${GREEN}私钥生成完成! 公钥: $(cat ~/.ssh/id_rsa.pub")${NC}"
    fi
elif [ "$1" = "add" ]; then
    # 添加公钥
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    if [ -n "$2" ]; then
        PUBKEY="$2"
    else
        echo -e "${GREEN}进入交互模式: 粘贴公钥 (支持多行, Ctrl+D 结束)${NC}"
        PUBKEY=$(cat)
    fi
    if grep -q "$PUBKEY" ~/.ssh/authorized_keys; then
        echo -e "${RED}公钥已存在.${NC}"
    else
        echo "$PUBKEY" >> ~/.ssh/authorized_keys
        echo -e "${GREEN}公钥添加完成!${NC}"
    fi
else
    echo -e "${RED}用法: keys.sh generate [--random] 或 keys.sh add [pubkey]${NC}"
    echo "无pubkey参数时进入交互模式."
    exit 1
fi
