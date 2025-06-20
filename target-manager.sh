#!/bin/bash

# 定义文件和目录路径
CONFIG_FILE="$HOME/.ssh_targets/targets.conf"
KEYS_DIR="$HOME/.ssh_targets/keys"

# 确保配置文件和目录存在
mkdir -p "$KEYS_DIR"
touch "$CONFIG_FILE"

# 函数：列出所有目标
list_targets() {
    echo "--- 目标服务器列表 ---"
    if [ ! -s "$CONFIG_FILE" ]; then
        echo "配置文件为空。请使用 '-a' 命令添加新目标。"
        return
    fi
    
    HEADER="别名|IP 地址|用户名|端口|私钥文件|状态"
    
    DATA=$(while IFS= read -r line || [[ -n "$line" ]]; do
        ALIAS=$(echo "$line" | awk '{print $1}')
        IP=$(echo "$line" | awk '{print $2}')
        USER=$(echo "$line" | awk '{print $3}')
        PORT=$(echo "$line" | awk '{print $4}')
        KEY_FILE=$(echo "$line" | awk '{print $5}')
        
        STATUS="[  OK  ]"
        if [ ! -f "$KEYS_DIR/$KEY_FILE" ]; then
            STATUS="[ 密钥丢失 ]"
        fi
        
        echo "$ALIAS|$IP|$USER|$PORT|$KEY_FILE|$STATUS"
    done < "$CONFIG_FILE")

    (echo "$HEADER"; echo "$DATA") | column -t -s '|'
}

# 函数：添加新目标
add_target() {
    local ALIAS
    if [ -n "$1" ]; then
        ALIAS="$1"
        echo "正在添加别名: $ALIAS"
    else
        read -p "输入一个简短的别名 (例如: web-01): " ALIAS
    fi

    if [ -z "$ALIAS" ]; then
        echo "错误: 别名不能为空。"
        exit 1
    fi

    if grep -q "^$ALIAS " "$CONFIG_FILE"; then
        echo "错误: 别名 '$ALIAS' 已存在。"
        exit 1
    fi

    read -p "输入目标的 IP 地址 (IPv4 or IPv6): " IP
    read -p "输入登录用户名 (默认: root): " USER
    USER=${USER:-root}
    
    read -p "输入端口号 (默认: 22): " PORT
    PORT=${PORT:-22}
    
    SUGGESTED_KEY_FILE="${ALIAS}.key"
    read -p "输入私钥文件名 (默认: $SUGGESTED_KEY_FILE): " KEY_FILE
    KEY_FILE=${KEY_FILE:-$SUGGESTED_KEY_FILE}
    
    # --- 新增：自动配置私钥 ---
    echo "--------------------------------------------------"
    echo "下一步：配置私钥。"
    echo "您可以立即粘贴私钥内容，脚本将自动为您保存。"
    echo "完成后按 Ctrl+D 结束输入。"
    echo "如果想稍后手动配置，请直接按 Ctrl+D 跳过。"
    echo "请粘贴私钥内容:"
    
    PRIVATE_KEY=$(cat) # 从标准输入读取，直到遇到EOF(Ctrl+D)
    
    if [ -n "$PRIVATE_KEY" ]; then
        KEY_PATH="$KEYS_DIR/$KEY_FILE"
        echo "$PRIVATE_KEY" > "$KEY_PATH"
        chmod 600 "$KEY_PATH"
        echo "✅ 私钥已成功保存并设置权限: $KEY_PATH"
    else
        echo "您跳过了自动配置。请记得稍后手动创建并配置私钥文件:"
        echo "   $KEYS_DIR/$KEY_FILE"
        echo "并设置权限: chmod 600 $KEYS_DIR/$KEY_FILE"
    fi
    # ---------------------------

    echo "$ALIAS $IP $USER $PORT $KEY_FILE" >> "$CONFIG_FILE"
    echo "✅ 目标 '$ALIAS' 已成功添加到配置文件中。"
}

# 函数：删除目标
remove_target() {
    local ALIAS_TO_REMOVE
    if [ -n "$1" ]; then
        ALIAS_TO_REMOVE="$1"
    else
        list_targets
        echo ""
        read -p "请输入您想删除的目标别名: " ALIAS_TO_REMOVE
    fi

    if [ -z "$ALIAS_TO_REMOVE" ]; then
        echo "操作取消。"
        exit 1
    fi

    if ! grep -q "^$ALIAS_TO_REMOVE " "$CONFIG_FILE"; then
        echo "错误: 别名 '$ALIAS_TO_REMOVE' 不存在。"
        exit 1
    fi
    
    KEY_FILE=$(grep "^$ALIAS_TO_REMOVE " "$CONFIG_FILE" | awk '{print $5}')
    
    sed -i.bak "/^$ALIAS_TO_REMOVE /d" "$CONFIG_FILE"
    
    echo "✅ 目标 '$ALIAS_TO_REMOVE' 已从配置中删除。"
    
    if [ -f "$KEYS_DIR/$KEY_FILE" ]; then
        read -p "是否同时删除关联的私钥文件 '$KEYS_DIR/$KEY_FILE'? (y/n): " CONFIRM
        if [[ "$CONFIRM" == "y" ]]; then
            rm "$KEYS_DIR/$KEY_FILE"
            echo "🔑 私钥文件已删除。"
        fi
    fi
}

# --- 主逻辑：解析命令行参数 ---
if [ $# -eq 0 ]; then
    list_targets
    exit 0
fi

case "$1" in
    -a|--add)
        add_target "$2"
        ;;
    -r|--remove)
        remove_target "$2"
        ;;
    -l|--list)
        list_targets
        ;;
    *)
        echo "错误: 未知参数 '$1'"
        echo "用法: $0 [-a|--add [别名]] [-r|--remove [别名]] [-l|--list]"
        exit 1
        ;;
esac
