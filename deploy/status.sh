#!/bin/bash
# RustDesk 服务端健康检查
# 说明：本脚本全程只读，不会修改任何文件、配置或服务状态。
# 用法：bash /opt/rustdesk/tools/status.sh

echo "=========================================="
echo " RustDesk 服务端健康检查"
echo " 时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo

# ---------- 1. 服务运行状态 ----------
echo "【服务状态】"
for svc in rustdesksignal rustdeskrelay; do
    state=$(systemctl is-active "$svc" 2>/dev/null)
    if [ "$state" = "active" ]; then
        # 取服务启动时间，便于判断是否发生过意外重启
        since=$(systemctl show "$svc" -p ActiveEnterTimestamp --value 2>/dev/null)
        echo "  ✅ $svc 运行中（启动于 ${since:-未知}）"
    else
        echo "  ❌ $svc 状态异常：${state:-未知}"
    fi
done
echo

# ---------- 2. 进程数检查 ----------
# 曾经踩过的坑：直接替换二进制后重启会导致旧进程残留，
# 同一服务跑多个进程争抢端口，引发连接不稳定。正常情况下各只应有 1 个。
echo "【进程数量】"
for proc in hbbs hbbr; do
    cnt=$(pgrep -x "$proc" | wc -l)
    if [ "$cnt" -eq 1 ]; then
        echo "  ✅ $proc：1 个进程（PID $(pgrep -x "$proc")）"
    elif [ "$cnt" -eq 0 ]; then
        echo "  ❌ $proc：进程不存在"
    else
        echo "  ⚠️  $proc：发现 $cnt 个进程，存在残留！需要 systemctl restart 清理"
        pgrep -x "$proc" | sed 's/^/       PID /'
    fi
done
echo

# ---------- 3. 端口监听 ----------
# 21115 NAT检测 / 21116 注册与打洞(TCP+UDP) / 21117 中继 / 21118 ws / 21119 ws中继
echo "【端口监听】"
for port in 21115 21116 21117 21118 21119; do
    if ss -lntu 2>/dev/null | grep -q ":${port}\b"; then
        echo "  ✅ $port 已监听"
    else
        echo "  ❌ $port 未监听"
    fi
done
echo

# ---------- 4. 最近注册的设备 ----------
echo "【最近 10 分钟在线设备】"
online=$(journalctl -u rustdesksignal --since "10 min ago" --no-pager -q 2>/dev/null \
    | grep -oE 'update_pk [0-9]+' | awk '{print $2}' | sort -u)
if [ -n "$online" ]; then
    echo "$online" | sed 's/^/  • 设备 /'
    echo "  合计：$(echo "$online" | wc -l) 台"
else
    echo "  （无设备上报心跳）"
fi
echo

# ---------- 5. 设备总数 ----------
echo "【设备总数】"
DB=/opt/rustdesk/db_v2.sqlite3
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
    total=$(sqlite3 "file:${DB}?mode=ro" "SELECT COUNT(*) FROM peers;" 2>/dev/null)
    blocked=$(sqlite3 "file:${DB}?mode=ro" "SELECT COUNT(*) FROM peers WHERE status=-1;" 2>/dev/null)
    echo "  已注册：${total:-查询失败} 台，已禁用：${blocked:-0} 台"
else
    # 服务器未安装 sqlite3 命令行工具时跳过，不作为错误
    echo "  （未安装 sqlite3 命令行工具，跳过）"
fi
echo

# ---------- 6. 磁盘与数据库体积 ----------
echo "【磁盘空间】"
df -h /opt | tail -1 | awk '{print "  根分区：已用 "$3" / 总共 "$2"（"$5"）"}'
[ -f "$DB" ] && echo "  数据库：$(du -h "$DB" | awk '{print $1}')"
echo

# ---------- 7. 最近的错误日志 ----------
echo "【最近 1 小时的错误日志】"
errs=$(journalctl -u rustdesksignal -u rustdeskrelay --since "1 hour ago" \
    --no-pager -q 2>/dev/null | grep -iE 'error|panic|failed|refused' | tail -10)
if [ -n "$errs" ]; then
    echo "$errs" | sed 's/^/  /'
else
    echo "  ✅ 无错误"
fi
echo

echo "=========================================="
echo " 检查完成（本次未修改任何内容）"
echo "=========================================="
