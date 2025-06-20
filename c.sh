#!/bin/bash

# 定义文件和目录路径
CONFIG_FILE="$HOME/.ssh_targets/targets.conf"
KEYS_DIR="$HOME/.ssh_targets/keys"
MANAGER_SCRIPT="$HOME/.ssh_targets/scripts/target-manager.sh"

# 如果没有提供参数，则列出可用目标
if [ -z "$1" ]; then
    # 使用 bash 执行 manager 脚本以避免权限问题和 sourcing 问题
    bash "$MANAGER_SCRIPT" list
    echo -e "\n用法: $0 <目标别名>"
    exit 1
fi

TARGET_ALIAS="$1"

# 从配置文件查找目标信息
TARGET_INFO=$(grep "^$TARGET_ALIAS " "$CONFIG_FILE")

if [ -z "$TARGET_INFO" ]; then
    echo "错误: 目标别名 '$TARGET_ALIAS' 未找到。"
    exit 1
fi

# 解析信息 (现在有5个字段)
IP=$(echo "$TARGET_INFO" | awk '{print $2}')
USER=$(echo "$TARGET_INFO" | awk '{print $3}')
PORT=$(echo "$TARGET_INFO" | awk '{print $4}')
KEY_FILE=$(echo "$TARGET_INFO" | awk '{print $5}')
FULL_KEY_PATH="$KEYS_DIR/$KEY_FILE"

# 检查私钥文件是否存在
if [ ! -f "$FULL_KEY_PATH" ]; then
    echo "错误: 找不到目标 '$TARGET_ALIAS' 所需的私钥文件!"
    echo "期望路径: $FULL_KEY_PATH"
    echo "请使用管理脚本添加私钥后重试。"
    exit 1
fi

# 执行SSH连接 (新增 -p $PORT 参数)
echo "正在连接到 $TARGET_ALIAS ($USER@$IP:$PORT)..."
ssh -i "$FULL_KEY_PATH" -p "$PORT" "$USER@$IP"
