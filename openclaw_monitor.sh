#!/bin/bash

# OpenClaw 进程监控自动恢复脚本
# 功能：每5分钟检测一次，挂了就用备份配置恢复并重启

# ============ 配置区域 ============
BACKUP_CONFIG="$HOME/.openclaw/openclaw.json.bak"
CONFIG="$HOME/.openclaw/openclaw.json"
LOG_FILE="$HOME/.openclaw/monitor.log"
INTERVAL=300  # 5分钟 = 300秒

# ============ 函数定义 ============

# 检测进程是否存活
check_openclaw() {
    # 检查 openclaw-gateway 主进程（核心）
    if pgrep -x "openclaw-gateway" > /dev/null 2>&1; then
        return 0
    fi
    
    # 备选：检查 openclaw-gateway 的完整匹配
    if pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# 记录日志
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 恢复配置并重启
do_restore_and_restart() {
    log_message "⚠️ 检测到 OpenClaw 进程异常，开始恢复流程..."
    
    # 检查备份文件是否存在
    if [ ! -f "$BACKUP_CONFIG" ]; then
        log_message "❌ 错误：备份文件不存在 ($BACKUP_CONFIG)"
        return 1
    fi
    
    # 检查备份文件修改时间是否在5分钟内（防手贱设计）
    CURRENT_TIME=$(date +%s)
    BACKUP_mtime=$(stat -c %Y "$BACKUP_CONFIG" 2>/dev/null || stat -f %m "$BACKUP_CONFIG" 2>/dev/null)
    
    if [ -z "$BACKUP_mtime" ]; then
        log_message "❌ 无法获取备份文件的修改时间"
        return 1
    fi
    
    TIME_DIFF=$((CURRENT_TIME - BACKUP_mtime))
    
    if [ "$TIME_DIFF" -gt 300 ]; then
        log_message "⏰ 备份文件超过 5 分钟未更新（$(($TIME_DIFF / 60)) 分钟前），可能是手动重启中，跳过自动恢复"
        log_message "💡 如需强制恢复，请先更新备份文件的修改时间: touch $BACKUP_CONFIG"
        return 1
    fi
    
    log_message "✅ 备份文件是新鲜的（${TIME_DIFF} 秒前创建），可以安全恢复"
    
    # 先备份当前（万一有问题还能回滚）
    if [ -f "$CONFIG" ]; then
        BROKEN_BACKUP="${CONFIG}.broken.$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG" "$BROKEN_BACKUP"
        log_message "📦 已备份当前配置到: $BROKEN_BACKUP"
    fi
    
    # 用备份替换当前配置
    cp "$BACKUP_CONFIG" "$CONFIG"
    log_message "✅ 已用备份配置替换当前配置"
    
    # 尝试重启 OpenClaw
    log_message "🔄 正在执行重启..."
    openclaw gateway restart
    
    if [ $? -eq 0 ]; then
        log_message "✅ OpenClaw 重启成功"
        sleep 3  # 等待启动
        if check_openclaw; then
            log_message "🎉 进程检测正常，恢复完成"
        else
            log_message "⚠️ 重启后进程检测仍失败，可能需要人工检查"
        fi
    else
        log_message "❌ OpenClaw restart 命令执行失败"
        return 1
    fi
}

# ============ 主逻辑 ============

log_message "🚀 OpenClaw 监控脚本启动 (PID: $$)"
log_message "📋 配置: 每 ${INTERVAL}秒检测一次 | 备份: $BACKUP_CONFIG"

# 检查备份文件
if [ ! -f "$BACKUP_CONFIG" ]; then
    log_message "❌ 警告：备份配置不存在 ($BACKUP_CONFIG)，请先创建备份"
    echo "请运行: cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak"
    exit 1
fi

# 检查备份新鲜度（超过5分钟警告）
CURRENT_TIME=$(date +%s)
BACKUP_mtime=$(stat -c %Y "$BACKUP_CONFIG" 2>/dev/null || stat -f %m "$BACKUP_CONFIG" 2>/dev/null)
if [ -n "$BACKUP_mtime" ]; then
    TIME_DIFF=$((CURRENT_TIME - BACKUP_mtime))
    if [ "$TIME_DIFF" -gt 300 ]; then
        log_message "⚠️ 警告：备份文件已过期 ($(($TIME_DIFF / 60)) 分钟)，请先更新: touch $BACKUP_CONFIG"
    else
        log_message "✅ 备份文件新鲜（${TIME_DIFF} 秒前）"
    fi
fi

# 监控循环
while true; do
    if check_openclaw; then
        log_message "💚 OpenClaw 运行正常"
    else
        log_message "💔 OpenClaw 进程异常/未运行"
        do_restore_and_restart
    fi
    
    sleep "$INTERVAL"
done
