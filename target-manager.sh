#!/bin/bash

# 定义文件和目录路径
CONFIG_FILE="$HOME/.ssh_targets/targets.conf"
KEYS_DIR="$HOME/.ssh_targets/keys"

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 函数：列出所有目标
list_targets() {
    echo -e "--- 目标服务器列表 ---"
    if [ ! -s "$CONFIG_FILE" ]; then
        echo "配置文件为空。请使用 '-a' 命令添加新目标。"
        return
    fi
    
    local HEADER

    # --- 新增：智能检测 Locale 并选择表头 ---
    if [[ "$LANG" == *.UTF-8 ]] || [[ "$LANG" == *.utf8 ]]; then
        # 系统环境支持 UTF-8，使用中文表头
        HEADER="别名|IP 地址|用户名|端口|私钥文件|状态"
    else
        # 系统环境不支持 UTF-8，回退到英文表头并提示
        echo -e "${YELLOW}警告: 检测到您的系统环境可能不支持UTF-8，已临时切换为英文表头。${NC}"
        HEADER="Alias|IP_Address|User|Port|Key_File|Status"
    fi
    # ----------------------------------------

    # 准备数据，并检查密钥状态
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

    # 使用 column 命令进行美化对齐
    (echo "$HEADER"; echo "$DATA") | column -t -s '|'
}

# 函数：添加新目标 (无改动)
add_target() {
    local ALIAS
    if [ -n "$1" ]; then
        ALIAS="$1"
        echo "正在添加别名: $ALIAS"
    else
        read -p "输入一个简短的别名 (例如: web-01): " ALIAS
    fi

    if [ -z "$ALIAS" ]; then
        echo -e "${RED}错误: 别名不能为空。${NC}"
        exit 1
    fi

    if grep -q "^$ALIAS " "$CONFIG_FILE"; then
        echo -e "${RED}错误: 别名 '$ALIAS' 已存在。${NC}"
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
    
    echo "--------------------------------------------------"
    echo "下一步：配置私钥。"
    echo "您可以立即粘贴私钥内容，脚本将自动为您保存。"
    echo "完成后按 Ctrl+D 结束输入。"
    echo "如果想稍后手动配置，请直接按 Ctrl+D 跳过。"
    echo "请粘贴私钥内容:"
    
    PRIVATE_KEY=$(cat)
    
    if [ -n "$PRIVATE_KEY" ]; then
        KEY_PATH="$KEYS_DIR/$KEY_FILE"
        echo "$PRIVATE_KEY" > "$KEY_PATH"
        chmod 600 "$KEY_PATH"
        echo -e "${GREEN}✅ 私钥已成功保存并设置权限: $KEY_PATH${NC}"
    else
        echo -e "${YELLOW}您跳过了自动配置。请记得稍后手动创建并配置私钥文件:${NC}"
        echo "   $KEYS_DIR/$KEY_FILE"
        echo -e "${YELLOW}并设置权限: chmod 600 $KEYS_DIR/$KEY_FILE${NC}"
    fi

    echo "$ALIAS $IP $USER $PORT $KEY_FILE" >> "$CONFIG_FILE"
    echo -e "${GREEN}✅ 目标 '$ALIAS' 已成功添加到配置文件中。${NC}"
}

# 函数：删除目标 (无改动)
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
        echo -e "${RED}错误: 别名 '$ALIAS_TO_REMOVE' 不存在。${NC}"
        exit 1
    fi
    
    KEY_FILE=$(grep "^$ALIAS_TO_REMOVE " "$CONFIG_FILE" | awk '{print $5}')
    
    sed -i.bak "/^$ALIAS_TO_REMOVE /d" "$CONFIG_FILE"
    
    echo -e "${GREEN}✅ 目标 '$ALIAS_TO_REMOVE' 已从配置中删除。${NC}"
    
    if [ -f "$KEYS_DIR/$KEY_FILE" ]; then
        read -p "$(echo -e ${YELLOW}"是否同时删除关联的私钥文件 '$KEYS_DIR/$KEY_FILE'? (y/n): "${NC})" CONFIRM
        if [[ "$CONFIRM" == "y" ]]; then
            rm "$KEYS_DIR/$KEY_FILE"
            echo -e "🔑 ${GREEN}私钥文件已删除。${NC}"
        fi
    fi
}

# 主逻辑 (无改动)
if [ $# -eq 0 ]; then
    list_targets
    exit 0
fi

case "$1" in
    -a|--add) add_target "$2" ;;
    -r|--remove) remove_target "$2" ;;
    -l|--list) list_targets ;;
    *)
        echo -e "${RED}错误: 未知参数 '$1'${NC}"
        echo "用法: $0 [-a|--add [别名]] [-r|--remove [别名]] [-l|--list]"
        exit 1
        ;;
esac
