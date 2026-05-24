#!/usr/bin/env python3
"""RustDesk 管理后台 API 服务
启动方式：ADMIN_PASSWORD=你的密码 python3 admin_api.py
"""

import os
import re
import sqlite3
import subprocess
from datetime import datetime, timedelta
from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

DB_PATH = os.environ.get("DB_PATH", "/opt/rustdesk/db_v2.sqlite3")
BLACKLIST_PATH = os.environ.get("BLACKLIST_PATH", "/opt/rustdesk/blacklist.txt")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "")
ONLINE_MINUTES = 10

app = FastAPI(title="RustDesk Admin API")
security = HTTPBearer()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)):
    if not ADMIN_PASSWORD:
        raise HTTPException(status_code=500, detail="未配置管理员密码")
    if creds.credentials != ADMIN_PASSWORD:
        raise HTTPException(status_code=401, detail="密码错误")
    return creds.credentials


def get_db():
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def read_blocklist() -> list:
    if not os.path.exists(BLACKLIST_PATH):
        return []
    with open(BLACKLIST_PATH) as f:
        return [ln.strip() for ln in f if ln.strip()]


def write_blocklist(ids: list):
    with open(BLACKLIST_PATH, "w") as f:
        f.write("\n".join(ids) + ("\n" if ids else ""))


def run_journal(unit: str, since: str = None, lines: int = None) -> str:
    cmd = ["journalctl", "-u", unit, "--no-pager", "-q"]
    if since:
        cmd += ["--since", since]
    if lines:
        cmd += ["-n", str(lines)]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return r.stdout
    except Exception:
        return ""


_IP = r"\d+\.\d+\.\d+\.\d+"


def parse_online(minutes: int = ONLINE_MINUTES) -> dict:
    since = (datetime.now() - timedelta(minutes=minutes)).strftime("%Y-%m-%d %H:%M:%S")
    output = run_journal("rustdesksignal", since=since)
    devices = {}
    pat = re.compile(
        r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})'
        r'.*?update_pk (\S+) \[::ffff:(' + _IP + r')'
    )
    for m in pat.finditer(output):
        devices[m.group(2)] = {"last_seen": m.group(1), "last_ip": m.group(3)}
    return devices


def parse_seen(days: int = 30) -> dict:
    since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
    output = run_journal("rustdesksignal", since=since)
    devices = {}
    pat = re.compile(
        r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})'
        r'.*?update_pk (\S+) \[::ffff:(' + _IP + r')'
    )
    for m in pat.finditer(output):
        t, pid, ip = m.group(1), m.group(2), m.group(3)
        if pid not in devices or t > devices[pid]["last_seen"]:
            devices[pid] = {"last_seen": t, "last_ip": ip}
    return devices


def parse_sessions(limit: int = 100) -> list:
    output = run_journal("rustdeskrelay", lines=3000)
    sessions = {}
    ip_to_sid = {}

    re_new = re.compile(
        r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)'
        r'.*?New relay request (\S+) from \[::ffff:(' + _IP + r')'
    )
    re_pair = re.compile(r'Relayrequest (\S+) from.*?got paired')
    re_close = re.compile(
        r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)'
        r'.*?Relay of \[::ffff:(' + _IP + r').*?closed'
    )

    for line in output.splitlines():
        m = re_new.search(line)
        if m:
            t, sid, ip = m.group(1), m.group(2), m.group(3)
            if not sid.startswith("scanner-"):
                sessions[sid] = {
                    "id": sid, "start_time": t, "ip": ip,
                    "paired": False, "end_time": None
                }
                ip_to_sid[ip] = sid
            continue
        m = re_pair.search(line)
        if m:
            sid = m.group(1)
            if sid in sessions:
                sessions[sid]["paired"] = True
            continue
        m = re_close.search(line)
        if m:
            t, ip = m.group(1), m.group(2)
            sid = ip_to_sid.get(ip)
            if sid and sid in sessions and not sessions[sid]["end_time"]:
                sessions[sid]["end_time"] = t
                ip_to_sid.pop(ip, None)

    result = sorted(sessions.values(), key=lambda x: x["start_time"], reverse=True)
    for s in result:
        if s["start_time"] and s["end_time"]:
            try:
                fmt = "%Y-%m-%d %H:%M:%S.%f"
                delta = (datetime.strptime(s["end_time"][:26], fmt) -
                         datetime.strptime(s["start_time"][:26], fmt))
                s["duration_seconds"] = max(0, int(delta.total_seconds()))
            except Exception:
                s["duration_seconds"] = None
        else:
            s["duration_seconds"] = None
    return result[:limit]


def svc_active(name: str) -> bool:
    try:
        r = subprocess.run(["systemctl", "is-active", name],
                           capture_output=True, text=True, timeout=3)
        return r.stdout.strip() == "active"
    except Exception:
        return False


@app.get("/api/stats")
def stats(_token=Depends(verify_token)):
    try:
        conn = get_db()
        total = conn.execute("SELECT COUNT(*) FROM peers").fetchone()[0]
        conn.close()
    except Exception:
        total = 0
    online = parse_online()
    all_sessions = parse_sessions(limit=500)
    today = datetime.now().strftime("%Y-%m-%d")
    today_count = sum(
        1 for s in all_sessions
        if s["start_time"].startswith(today) and s["paired"]
    )
    return {
        "total_devices": total,
        "online_count": len(online),
        "today_sessions": today_count,
        "hbbs_running": svc_active("rustdesksignal"),
        "hbbr_running": svc_active("rustdeskrelay"),
    }


@app.get("/api/devices")
def devices(_token=Depends(verify_token)):
    blocked = read_blocklist()
    online = parse_online()
    seen = parse_seen()
    try:
        conn = get_db()
        cur = conn.execute("SELECT * FROM peers ORDER BY created_at DESC")
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        conn.close()
    except Exception as e:
        return {"devices": [], "error": str(e)}
    result = []
    for row in rows:
        d = dict(zip(cols, row))
        pid = d.get("id", "")
        s = seen.get(pid, {})
        result.append({
            "id": pid,
            "created_at": d.get("created_at"),
            "last_seen": s.get("last_seen"),
            "last_ip": s.get("last_ip"),
            "online": pid in online,
            "blocked": pid in blocked,
        })
    return {"devices": result}


@app.get("/api/sessions")
def sessions(_token=Depends(verify_token)):
    return {"sessions": parse_sessions(100)}


@app.get("/api/blocklist")
def blocklist(_token=Depends(verify_token)):
    return {"blocklist": read_blocklist()}


@app.post("/api/blocklist/{device_id}")
def block(device_id: str, _token=Depends(verify_token)):
    lst = read_blocklist()
    if device_id not in lst:
        lst.append(device_id)
        write_blocklist(lst)
    return {"ok": True}


@app.delete("/api/blocklist/{device_id}")
def unblock(device_id: str, _token=Depends(verify_token)):
    lst = read_blocklist()
    if device_id in lst:
        lst.remove(device_id)
        write_blocklist(lst)
    return {"ok": True}


if __name__ == "__main__":
    if not ADMIN_PASSWORD:
        print("错误：请设置 ADMIN_PASSWORD 环境变量")
        exit(1)
    uvicorn.run(app, host="0.0.0.0", port=21120)
