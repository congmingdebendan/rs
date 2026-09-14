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
        # 取服务启动时间，便于判断是否发生过意外重启。
        # 注意：不能用 systemctl show --value，该参数需 systemd 230+，
        # CentOS 7 自带 systemd 219 不支持，只能自己切掉等号前缀。
        since=$(systemctl show "$svc" -p ActiveEnterTimestamp 2>/dev/null | cut -d= -f2-)
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

# ---------- 4. 最近活跃的设备 ----------
# 重要：hbbs 的常规心跳不写日志，update_pk 只在设备首次注册或公网 IP
# 变化时才打印。所以这里统计的是"最近 24 小时上报过注册信息的设备"，
# 不等于"当前在线设备"。窗口取太短（如 10 分钟）几乎永远是空的。
echo "【最近 24 小时上报注册的设备】"
active=$(journalctl -u rustdesksignal --since "24 hours ago" --no-pager -q 2>/dev/null \
    | grep -oE 'update_pk [0-9]+' | awk '{print $2}' | sort -u)
if [ -n "$active" ]; then
    echo "$active" | sed 's/^/  • 设备 /'
    echo "  合计：$(echo "$active" | wc -l) 台"
else
    echo "  （24 小时内无设备上报，可能都未重启客户端或未换网络）"
fi
echo

# ---------- 4.5 中继会话 ----------
# 相比 update_pk，中继请求反映的是真实的连接活动，参考价值更高
echo "【最近 24 小时中继会话】"
relay_cnt=$(journalctl -u rustdeskrelay --since "24 hours ago" --no-pager -q 2>/dev/null \
    | grep -c 'New relay request')
paired_cnt=$(journalctl -u rustdeskrelay --since "24 hours ago" --no-pager -q 2>/dev/null \
    | grep -c 'got paired')
echo "  发起 ${relay_cnt:-0} 次，成功配对 ${paired_cnt:-0} 次"
echo

# ---------- 5. 设备总数 ----------
echo "【设备总数】"
DB=/opt/rustdesk/db_v2.sqlite3
if [ ! -f "$DB" ]; then
    echo "  （未找到数据库 $DB）"
elif ! command -v sqlite3 >/dev/null 2>&1; then
    echo "  （未安装 sqlite3 命令行工具，跳过）"
else
    # 先复制一份再查询，绝不对 hbbs 正在使用的数据库加任何锁。
    # 库只有几十 KB，复制开销可忽略。
    TMPDB=$(mktemp /tmp/rdstat.XXXXXX)
    cp "$DB" "$TMPDB" 2>/dev/null
    out=$(sqlite3 "$TMPDB" "SELECT COUNT(*) FROM peers;" 2>&1)
    if echo "$out" | grep -qE '^[0-9]+$'; then
        blocked=$(sqlite3 "$TMPDB" "SELECT COUNT(*) FROM peers WHERE status=-1;" 2>/dev/null)
        echo "  已注册：${out} 台，已禁用：${blocked:-0} 台"
    elif echo "$out" | grep -qi 'without'; then
        # CentOS 7 自带 sqlite3 3.7.17，不认识 hbbs 建表用的 WITHOUT ROWID
        # 语法（需 3.8.2+），连 schema 都解析不了。属环境限制，非故障。
        echo "  （跳过：sqlite3 $(sqlite3 -version | awk '{print $1}') 过旧，"
        echo "    不支持 WITHOUT ROWID 语法，需 3.8.2 以上版本）"
    else
        echo "  （查询失败：${out}）"
    fi
    rm -f "$TMPDB"
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
