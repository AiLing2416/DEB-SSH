#!/bin/bash

# =========================================
# Change SSH Port
# -----------------------------------------
# Author: Gemini
# Version: 1.0
# Description: Interactively change the port number of the SSH service.
# The script will back up the original configuration file, update the SSH configuration,
# and open firewall ports as needed.
# =========================================

# --- 变量和常量定义 ---
SSH_CONFIG_FILE="/etc/ssh/sshd_config"
BACKUP_DIR="/var/backups/ssh_config_backups"
LOG_FILE="/var/log/ssh_port_change.log"

# --- 函数定义 ---

# 记录日志
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "错误: 此脚本需要 root 权限才能运行。"
        echo "请使用 'sudo' 运行此脚本。"
        exit 1
    fi
}

# 备份 SSH 配置文件
backup_config() {
    log_message "正在备份 SSH 配置文件..."
    mkdir -p "$BACKUP_DIR" || { log_message "错误: 无法创建备份目录 $BACKUP_DIR"; exit 1; }
    local timestamp=$(date '+%Y%m%d%H%M%S')
    cp "$SSH_CONFIG_FILE" "$BACKUP_DIR/sshd_config.bak.$timestamp" || { log_message "错误: 备份失败。"; exit 1; }
    log_message "SSH 配置文件已备份至 $BACKUP_DIR/sshd_config.bak.$timestamp"
}

# 验证端口号是否有效
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1024 )) || (( port > 65535 )); then
        log_message "错误: 无效的端口号 '$port'。端口必须是 1024 到 65535 之间的数字。"
        return 1
    fi
    return 0
}

# 修改 SSH 端口
modify_ssh_port() {
    local new_port="$1"
    log_message "正在修改 SSH 端口为 $new_port..."

    # 检查是否存在 Port 配置行，如果存在则修改，否则添加
    if grep -qE "^\s*Port\s+[0-9]+" "$SSH_CONFIG_FILE"; then
        sed -i "s/^\s*Port\s+[0-9]\+/Port $new_port/" "$SSH_CONFIG_FILE" || { log_message "错误: 修改 SSH 端口失败。"; exit 1; }
    else
        echo "Port $new_port" >> "$SSH_CONFIG_FILE" || { log_message "错误: 添加 SSH 端口失败。"; exit 1; }
    fi
    log_message "SSH 端口已修改为 $new_port。"
}

# 更新防火墙规则
update_firewall() {
    local new_port="$1"
    log_message "正在更新防火墙规则..."

    if command -v ufw &> /dev/null; then
        # 针对 UFW (Ubuntu/Debian)
        log_message "检测到 UFW 防火墙。"
        local current_ssh_port=$(grep -E "^\s*Port\s+[0-9]+" "$SSH_CONFIG_FILE" | awk '{print $2}')
        if [ -n "$current_ssh_port" ] && [ "$current_ssh_port" != "$new_port" ]; then
            log_message "正在关闭旧的 SSH 端口 $current_ssh_port..."
            ufw delete allow "$current_ssh_port/tcp" &>/dev/null
        fi
        log_message "正在开放新的 SSH 端口 $new_port..."
        ufw allow "$new_port/tcp" || { log_message "警告: 无法开放 UFW 端口 $new_port。请手动检查。"; }
        ufw reload &>/dev/null
    elif command -v firewall-cmd &> /dev/null; then
        # 针对 FirewallD (CentOS/RHEL)
        log_message "检测到 FirewallD 防火墙。"
        local current_ssh_port=$(grep -E "^\s*Port\s+[0-9]+" "$SSH_CONFIG_FILE" | awk '{print $2}')
        if [ -n "$current_ssh_port" ] && [ "$current_ssh_port" != "$new_port" ]; then
            log_message "正在关闭旧的 SSH 端口 $current_ssh_port..."
            firewall-cmd --permanent --remove-port="$current_ssh_port/tcp" &>/dev/null
        fi
        log_message "正在开放新的 SSH 端口 $new_port..."
        firewall-cmd --permanent --add-port="$new_port/tcp" || { log_message "警告: 无法开放 FirewallD 端口 $new_port。请手动检查。"; }
        firewall-cmd --reload &>/dev/null
    else
        log_message "未检测到 UFW 或 FirewallD。请手动配置您的防火墙以允许新端口 $new_port。"
    fi
}

# 重启 SSH 服务
restart_ssh_service() {
    log_message "正在重启 SSH 服务..."
    if systemctl is-active --quiet sshd; then
        systemctl restart sshd || { log_message "错误: 重启 SSH 服务失败。请手动检查。"; exit 1; }
        log_message "SSH 服务已成功重启。"
    else
        log_message "SSH 服务未运行或不存在 'sshd' 服务。请手动启动或检查服务名称。"
        exit 1
    fi
}

# --- 主程序逻辑 ---

echo "--- 欢迎使用 SSH 端口修改脚本 ---"
log_message "SSH 端口修改脚本启动。"

check_root

echo ""
read -p "请输入您要设置的新的 SSH 端口号 (例如: 2222，范围 1024-65535): " NEW_PORT

validate_port "$NEW_PORT" || { log_message "脚本终止。"; exit 1; }

echo ""
echo "您选择的新 SSH 端口号是: $NEW_PORT"
read -p "确认更改吗？(y/N): " confirm

if [[ "$confirm" =~ ^[yY]$ ]]; then
    backup_config
    modify_ssh_port "$NEW_PORT"
    update_firewall "$NEW_PORT"
    restart_ssh_service
    log_message "SSH 端口修改流程完成。您现在可以使用新端口 $NEW_PORT 连接 SSH。"
    echo ""
    echo "--- 脚本执行完毕 ---"
    echo "新的 SSH 端口是: $NEW_PORT"
    echo "请尝试使用新端口连接您的 SSH 服务。"
else
    log_message "用户取消了操作。脚本终止。"
    echo "操作已取消。SSH 端口未做任何更改。"
fi

echo ""
echo "日志文件位于: $LOG_FILE"
