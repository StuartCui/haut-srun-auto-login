#!/bin/sh
# ImmortalWRT 自动校园网认证脚本 v8
# 功能：自动等待网络 → 登录 → 掉线检测 → 定时重登 → 日志维护 → 掉线轮换账号
# 环境：ash 兼容（OpenWRT / ImmortalWRT）
# ------------------------------------------------------------

SRUN_DIR="/srun"
SRUN_BIN="$SRUN_DIR/srun"
SRUN_CFG="$SRUN_DIR/config.json"
ACCOUNTS_FILE="$SRUN_DIR/accounts.list"
LOG_MAIN="$SRUN_DIR/srun_main.log"
LOG_WATCHDOG="$SRUN_DIR/srun_watchdog.log"
STATE_FILE="$SRUN_DIR/srun_state.log"

MAX_LOGIN_LOGS=25
MAX_WATCH_LOGS=150
CHECK_INTERVAL=40
RELOGIN_INTERVAL=$((3*60))
MAX_WATCHDOG_SIZE=20480
KEEP_WATCHDOG_LINES=2000

# ============================================================
# 检测连接校园网的网络接口
find_available_interface() {
    # 检查phy1-sta0是否能ping通校园网服务器
    if ping -c 1 -W 1 -I phy1-sta0 172.16.154.130 >/dev/null 2>&1; then
        echo "phy1-sta0"
    # 检查phy0-sta0是否能ping通校园网服务器
    elif ping -c 1 -W 1 -I phy0-sta0 172.16.154.130 >/dev/null 2>&1; then
        echo "phy0-sta0"
    else
        # 如果都不能ping通，返回空
        echo ""
    fi
}

# ============================================================
wait_for_network() {
    echo "[$(date '+%F %T')] 等待校园网服务器可达..." | tee -a "$LOG_MAIN"
    while ! ping -c 1 -W 1 172.16.154.130 >/dev/null 2>&1; do
        sleep 1
    done
    echo "[$(date '+%F %T')] 网络就绪，开始认证..." | tee -a "$LOG_MAIN"
}

# ============================================================
# 登录（不切换账号）
do_login() {
    echo "====================================================" >> "$LOG_MAIN"
    echo "[$(date '+%F %T')] 执行 srun 自动认证（当前账号）..." | tee -a "$LOG_MAIN"

    if [ ! -f "$ACCOUNTS_FILE" ]; then
        echo "[$(date '+%F %T')] 未找到账号列表: $ACCOUNTS_FILE" | tee -a "$LOG_MAIN"
        return 1
    fi

    CURRENT=$(grep '^CURRENT_ACCOUNT=' "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    [ -z "$CURRENT" ] && CURRENT=1

    CFG_NAME=$(grep -v '^[[:space:]]*$' "$ACCOUNTS_FILE" | sed -n "${CURRENT}p" | tr -d '\r\n')
    CFG_PATH="$SRUN_DIR/$CFG_NAME"

    if [ ! -f "$CFG_PATH" ]; then
        echo "[$(date '+%F %T')] 找不到配置文件 $CFG_PATH" | tee -a "$LOG_MAIN"
        return 1
    fi

    cp -f "$CFG_PATH" "$SRUN_CFG"
    
    # 检测可用的网络接口
    INTERFACE=$(find_available_interface)
    if [ -n "$INTERFACE" ]; then
        # 修改配置文件中的if_name字段
        sed -i "s/\"if_name\": \"[^\"]*\"/\"if_name\": \"$INTERFACE\"/g" "$SRUN_CFG"
        echo "[$(date '+%F %T')] 自动检测到网络接口: $INTERFACE" | tee -a "$LOG_MAIN"
    else
        echo "[$(date '+%F %T')] 未检测到可用的网络接口" | tee -a "$LOG_MAIN"
    fi
    
    echo "[$(date '+%F %T')] 使用账号配置: $CFG_NAME (账号序号 $CURRENT)" | tee -a "$LOG_MAIN"

    if [ -x "$SRUN_BIN" ]; then
        "$SRUN_BIN" login -c "$SRUN_CFG" >> "$LOG_MAIN" 2>&1
        RESULT=$?
        if [ "$RESULT" -eq 0 ]; then
            echo "[$(date '+%F %T')] 登录成功 (退出码: $RESULT)" | tee -a "$LOG_MAIN"
            record_state "success" "$CURRENT"
        else
            echo "[$(date '+%F %T')] 登录失败 (退出码: $RESULT)" | tee -a "$LOG_MAIN"
        fi
    else
        echo "[$(date '+%F %T')] srun 文件不存在或无执行权限" | tee -a "$LOG_MAIN"
    fi
    echo "" >> "$LOG_MAIN"
}

# ============================================================
# 登录并切换到下一个账号（掉线时使用）
do_login_next() {
    echo "====================================================" >> "$LOG_MAIN"
    echo "[$(date '+%F %T')] 掉线检测失败，尝试切换账号重新登录..." | tee -a "$LOG_MAIN"

    if [ ! -f "$ACCOUNTS_FILE" ]; then
        echo "[$(date '+%F %T')] 未找到账号列表: $ACCOUNTS_FILE" | tee -a "$LOG_MAIN"
        return 1
    fi

    TOTAL=$(grep -v '^[[:space:]]*$' "$ACCOUNTS_FILE" | wc -l)
    CURRENT=$(grep '^CURRENT_ACCOUNT=' "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    [ -z "$CURRENT" ] && CURRENT=1
    NEXT=$((CURRENT + 1))
    [ "$NEXT" -gt "$TOTAL" ] && NEXT=1

    CFG_NAME=$(grep -v '^[[:space:]]*$' "$ACCOUNTS_FILE" | sed -n "${NEXT}p" | tr -d '\r\n')
    CFG_PATH="$SRUN_DIR/$CFG_NAME"

    cp -f "$CFG_PATH" "$SRUN_CFG"
    
    # 检测可用的网络接口
    INTERFACE=$(find_available_interface)
    if [ -n "$INTERFACE" ]; then
        # 修改配置文件中的if_name字段
        sed -i "s/\"if_name\": \"[^\"]*\"/\"if_name\": \"$INTERFACE\"/g" "$SRUN_CFG"
        echo "[$(date '+%F %T')] 自动检测到网络接口: $INTERFACE" | tee -a "$LOG_MAIN"
    else
        echo "[$(date '+%F %T')] 未检测到可用的网络接口" | tee -a "$LOG_MAIN"
    fi
    
    echo "[$(date '+%F %T')] 切换账号配置: $CFG_NAME (账号序号 $NEXT/$TOTAL)" | tee -a "$LOG_MAIN"

    if [ -x "$SRUN_BIN" ]; then
        "$SRUN_BIN" login -c "$SRUN_CFG" >> "$LOG_MAIN" 2>&1
        RESULT=$?
        if [ "$RESULT" -eq 0 ]; then
            echo "[$(date '+%F %T')] 登录成功 (退出码: $RESULT)" | tee -a "$LOG_MAIN"
            record_state "success" "$NEXT"
        else
            echo "[$(date '+%F %T')] 登录失败 (退出码: $RESULT)" | tee -a "$LOG_MAIN"
        fi
    fi
    echo "" >> "$LOG_MAIN"
}

# ============================================================
record_state() {
    STATUS="$1"
    CURRENT_ACCOUNT="$2"
    [ ! -f "$STATE_FILE" ] && touch "$STATE_FILE"
    LAST_SUCCESS=$(date '+%F %T')
    RECONNECTS=$(grep '^RECONNECTS=' "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    [ -z "$RECONNECTS" ] && RECONNECTS=0
    RECONNECTS=$((RECONNECTS + 1))
    {
        echo "LAST_SUCCESS=$LAST_SUCCESS"
        echo "RECONNECTS=$RECONNECTS"
        echo "CURRENT_ACCOUNT=$CURRENT_ACCOUNT"
    } > "$STATE_FILE"
    echo "[$LAST_SUCCESS] 已记录状态: 成功登录 $RECONNECTS 次，当前账号 #$CURRENT_ACCOUNT" | tee -a "$LOG_MAIN"
}

# ============================================================
trim_log() {
    FILE="$1"
    MAX="$2"
    COUNT=$(grep -c "====================================================" "$FILE" 2>/dev/null || echo 0)
    if [ "$COUNT" -gt "$MAX" ]; then
        tail -n $(($(wc -l < "$FILE") / $COUNT * $MAX)) "$FILE" > "${FILE}.tmp"
        mv "${FILE}.tmp" "$FILE"
        echo "[$(date '+%F %T')] 日志已清理，仅保留最近 $MAX 条记录。" | tee -a "$FILE"
    fi
}

trim_watchdog_log() {
    if [ -f "$LOG_WATCHDOG" ]; then
        SIZE=$(wc -c < "$LOG_WATCHDOG" 2>/dev/null)
        if [ "$SIZE" -gt "$MAX_WATCHDOG_SIZE" ]; then
            tail -n "$KEEP_WATCHDOG_LINES" "$LOG_WATCHDOG" > "${LOG_WATCHDOG}.tmp"
            mv "${LOG_WATCHDOG}.tmp" "$LOG_WATCHDOG"
            echo "[$(date '+%F %T')] Watchdog 日志过大，已截断为最近 $KEEP_WATCHDOG_LINES 行。" >> "$LOG_WATCHDOG"
        fi
    fi
}

# ============================================================
watchdog_loop() {
    echo "[$(date '+%F %T')] 启动掉线检测守护进程..." | tee -a "$LOG_WATCHDOG"
    LAST_LOGIN_TIME=$(date +%s)
    while true; do
        sleep "$CHECK_INTERVAL"

        if ! ping -c 1 -W 2 baidu.com >/dev/null 2>&1; then
            echo "[$(date '+%F %T')] 掉线检测失败，执行账号轮换登录..." | tee -a "$LOG_WATCHDOG"
            "$0" login_next
            trim_log "$LOG_MAIN" "$MAX_LOGIN_LOGS"
        else
            echo "[$(date '+%F %T')] 网络正常" | tee -a "$LOG_WATCHDOG"
        fi

        NOW=$(date +%s)
        if [ $((NOW - LAST_LOGIN_TIME)) -ge $RELOGIN_INTERVAL ]; then
            echo "[$(date '+%F %T')] 到达设置间隔，执行重登..." | tee -a "$LOG_WATCHDOG"
            "$0" login
            LAST_LOGIN_TIME=$NOW
        fi

        trim_log "$LOG_WATCHDOG" "$MAX_WATCH_LOGS"
        trim_watchdog_log
    done
}

# ============================================================
show_status() {
    echo "=================== 当前状态 ==================="
    if ping -c 1 -W 2 baidu.com >/dev/null 2>&1; then
        ONLINE="在线"
    else
        ONLINE="离线"
    fi
    RECONNECTS=$(grep '^RECONNECTS=' "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    LAST_SUCCESS=$(grep '^LAST_SUCCESS=' "$STATE_FILE" 2>/dev/null | cut -d'=' -f2-)
    CURRENT_ACCOUNT=$(grep '^CURRENT_ACCOUNT=' "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    [ -z "$RECONNECTS" ] && RECONNECTS="0"
    [ -z "$LAST_SUCCESS" ] && LAST_SUCCESS="无记录"
    [ -z "$CURRENT_ACCOUNT" ] && CURRENT_ACCOUNT="1"
    if pgrep -f "1008.sh watchdog" >/dev/null 2>&1; then
        WATCHDOG="运行中"
    else
        WATCHDOG="未运行"
    fi
    echo "网络状态:     $ONLINE"
    echo "重连次数:     $RECONNECTS"
    echo "上次登录时间: $LAST_SUCCESS"
    echo "当前账号序号: $CURRENT_ACCOUNT"
    echo "守护进程状态: $WATCHDOG"
    echo "================================================="
}

# ============================================================
case "$1" in
    start)
        wait_for_network
        "$0" login
        trim_log "$LOG_MAIN" "$MAX_LOGIN_LOGS"
        if ! pgrep -f "1008.sh watchdog" >/dev/null 2>&1; then
            "$0" watchdog &
            echo "[$(date '+%F %T')] 已启动守护进程" | tee -a "$LOG_MAIN"
        else
            echo "[$(date '+%F %T')] 守护进程已在运行，无需重复启动" | tee -a "$LOG_MAIN"
        fi
        ;;
    login)
        do_login
        ;;
    login_next)
        do_login_next
        ;;
    watchdog)
        watchdog_loop
        ;;
    status)
        show_status
        ;;
    *)
        echo "用法: $0 {start|login|login_next|watchdog|status}"
        ;;
esac