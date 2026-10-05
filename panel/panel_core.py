"""
Davida Core - Central VPN Management Service & REST API v3.0 (Stealth Telemetry Edition)
Provides user management, per-user PINs/passwords, accurate traffic stats,
passive kernel socket telemetry (Zero-RKN-Detection), multi-metric health scoring,
and web panel backend.
"""

import os
import sys
import json
import time
import re
import math
import socket
import hmac
import hashlib
import sqlite3
import threading
import html
import ipaddress
import secrets
import subprocess
import urllib.parse
import concurrent.futures
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from pathlib import Path

# --- CONFIGURATION ---
# Dynamic environment detection
if os.path.exists("/etc/vpn-davida"):
    ETC_DIR = "/etc/vpn-davida"
    APP_DIR = "/opt/vpn-davida-panel"
    LOG_BASENAME = "/var/log/nginx/vpn-davida-access.log"
    SSH_PORT = "23432"
    SSH_USER = "vpnadmin"
    LOCAL_IPS = ("127.0.0.1", "localhost", "198.51.100.11")
    DOMAIN = "vpn.example.com"
    WEB_PATH = Path("/var/www/vpn-ch.example.com")
    CORE_PATH = Path("/var/www/vpn-ch.example.com/_core")
else:
    ETC_DIR = "/etc/vpn-cluster"
    APP_DIR = "/opt/vpn-panel"
    LOG_BASENAME = "/var/log/nginx/vpn-cluster-access.log"
    SSH_PORT = "22"
    SSH_USER = "vpnadmin"
    LOCAL_IPS = ("127.0.0.1", "localhost", "198.51.100.10")
    DOMAIN = "vpn.example.com"
    WEB_PATH = Path("/var/www/vpn-ch.example.com")
    CORE_PATH = Path("/var/www/vpn-ch.example.com/_core")

PORT = 8888
HOST = "127.0.0.1"

def get_secret_key() -> bytes:
    import secrets
    secret_path = Path("/etc/vpn-davida/jwt_secret")
    if not secret_path.exists():
        secret_path = Path(f"{ETC_DIR}/jwt_secret")
    if not secret_path.exists():
        secret_path.parent.mkdir(parents=True, exist_ok=True)
        secret_path.write_bytes(secrets.token_bytes(32))
        try:
            secret_path.chmod(0o600)
        except Exception:
            pass
    return secret_path.read_bytes()

SECRET_KEY = get_secret_key()
SESSION_DURATION_SEC = 86400 * 7  # 7 days

MASTER_SECRET_FILE = Path(f"{ETC_DIR}/master_secret")

_cached_master_secret = None
_cached_secret_mtime = 0
_secret_lock = threading.Lock()

def get_master_password() -> str:
    global _cached_master_secret, _cached_secret_mtime
    with _secret_lock:
        if MASTER_SECRET_FILE.exists():
            try:
                st = MASTER_SECRET_FILE.stat()
                if _cached_master_secret is not None and st.st_mtime == _cached_secret_mtime:
                    return _cached_master_secret
                pwd = MASTER_SECRET_FILE.read_text(encoding="utf-8").strip()
                if pwd:
                    _cached_master_secret = pwd
                    _cached_secret_mtime = st.st_mtime
                    return pwd
            except Exception:
                pass
        raise RuntimeError("Master secret file missing")

def get_master_password_hash() -> str:
    return hashlib.sha256(get_master_password().encode()).hexdigest()

def rotate_cluster_master_password(new_password: str) -> dict:
    new_password = new_password.strip()
    if len(new_password) < 10:
        raise ValueError("Пароль должен содержать не менее 10 символов")
        
    if any(c in new_password for c in ['\n', '\r', "'", '"', ':', ';']):
        raise ValueError("Пароль содержит недопустимые символы")

    # 1. Update local secret file
    MASTER_SECRET_FILE.parent.mkdir(parents=True, exist_ok=True)
    MASTER_SECRET_FILE.write_text(new_password, encoding="utf-8")
    try:
        MASTER_SECRET_FILE.chmod(0o600)
    except Exception:
        pass

    try:
        subprocess.run(["sudo", "-n", "chpasswd"], input=f"{SSH_USER}:{new_password}\n", text=True, timeout=5)
    except Exception:
        pass

    global _cached_master_secret, _cached_secret_mtime
    with _secret_lock:
        _cached_master_secret = new_password
        _cached_secret_mtime = MASTER_SECRET_FILE.stat().st_mtime if MASTER_SECRET_FILE.exists() else time.time()

    # 2. Sync to other nodes
    updated = ["ch"]
    errors = {}

    for n in get_nodes():
        nid = n["id"]
        ip = n["ip"]
        if nid == "ch":
            continue
        try:
            cmd = [
                "ssh", "-i", str(CLUSTER_SSH_KEY), "-p", SSH_PORT,
                "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=4",
                "--", f"{SSH_USER}@{ip}",
                f"cat > {ETC_DIR}/master_secret && chmod 600 {ETC_DIR}/master_secret && awk \'{{print \"{SSH_USER}:\" $0}}\' {ETC_DIR}/master_secret | sudo -n chpasswd"
            ]
            res = subprocess.run(cmd, input=new_password, capture_output=True, text=True, timeout=8)
            if res.returncode == 0:
                updated.append(nid)
            else:
                errors[nid] = res.stderr[:100]
        except Exception as e:
            errors[nid] = str(e)

    log_system_memory(
        f"Выполнена ротация мастер-пароля кластера на узлах: {', '.join(updated)}",
        author="admin-web",
        category="CREDENTIAL_ROTATION",
        files=f"{ETC_DIR}/master_secret, /etc/shadow",
        rollback="N/A (Security rotation)"
    )

    return {"success": True, "updated_nodes": updated, "errors": errors}

USERS_FILE = Path(f"{ETC_DIR}/users.txt")
PASSWORDS_FILE = Path(f"{ETC_DIR}/passwords.json")
LOG_FILE = Path(LOG_BASENAME)
DB_PATH = Path(f"{APP_DIR}/metrics.db")
SYSTEM_MEMORY_FILE = Path(f"{ETC_DIR}/SYSTEM_MEMORY.md")
CHANGELOG_FILE = Path(f"{ETC_DIR}/CHANGELOG.md")
CLUSTER_SSH_KEY = Path(f"{ETC_DIR}/cluster_key")


NODES_FILE = Path(f"{ETC_DIR}/nodes.json")
_nodes_cache = None
_nodes_mtime = 0
_nodes_lock = threading.Lock()

def get_nodes():
    global _nodes_cache, _nodes_mtime
    with _nodes_lock:
        if NODES_FILE.exists():
            try:
                st = NODES_FILE.stat().st_mtime
                if st != _nodes_mtime or _nodes_cache is None:
                    _nodes_cache = json.loads(NODES_FILE.read_text(encoding="utf-8"))
                    _nodes_mtime = st
            except Exception:
                pass
        if _nodes_cache is None:
            _nodes_cache = []
        return _nodes_cache

# In-memory latest status cache (updated every 15s by collector)
_latest_node_status = {}
_status_lock = threading.Lock()

# --- METRICS DATABASE (SQLite) ---

def init_db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(DB_PATH, timeout=5) as conn:
        conn.execute("PRAGMA journal_mode = WAL;")
        conn.execute("PRAGMA busy_timeout = 5000;")
        conn.execute("""
            CREATE TABLE IF NOT EXISTS node_pings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER,
                node_id TEXT,
                latency_ms REAL,
                online INTEGER
            );
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_pings ON node_pings(node_id, timestamp);")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_pings_timestamp ON node_pings(timestamp);")

        conn.execute("""
            CREATE TABLE IF NOT EXISTS node_telemetry (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER,
                node_id TEXT,
                online INTEGER,
                active_sessions INTEGER DEFAULT 0,
                client_rtt_p50 REAL,
                client_rtt_p95 REAL,
                rtt_var REAL,
                retrans_rate_pct REAL,
                anycast_ms REAL,
                quality_score INTEGER,
                status_label TEXT
            );
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_telemetry ON node_telemetry(node_id, timestamp);")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_telemetry_timestamp ON node_telemetry(timestamp);")

        conn.execute("""
            CREATE TABLE IF NOT EXISTS user_xray_traffic (
                username TEXT PRIMARY KEY,
                bytes_down INTEGER DEFAULT 0,
                bytes_up INTEGER DEFAULT 0,
                last_seen INTEGER DEFAULT 0,
                is_online INTEGER DEFAULT 0,
                sessions_count INTEGER DEFAULT 0
            );
        """)

        # Long-term rollups: raw node samples stay 7 days; hourly rollups stay 90 days.
        conn.execute("""
            CREATE TABLE IF NOT EXISTS node_stats_hourly (
                hour_ts INTEGER NOT NULL,
                node_id TEXT NOT NULL,
                sample_count INTEGER NOT NULL DEFAULT 0,
                online_count INTEGER NOT NULL DEFAULT 0,
                uptime_pct REAL,
                avg_ping_ms REAL,
                avg_client_rtt_p50 REAL,
                avg_client_rtt_p95 REAL,
                max_client_rtt_p95 REAL,
                avg_rtt_var REAL,
                avg_retrans_rate_pct REAL,
                avg_anycast_ms REAL,
                avg_quality_score REAL,
                avg_active_sessions REAL,
                PRIMARY KEY (hour_ts, node_id)
            );
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_node_stats_hourly_node_hour ON node_stats_hourly(node_id, hour_ts);")

        # Per-user history begins at deployment; pre-existing cumulative totals are not reconstructable by day.
        conn.execute("""
            CREATE TABLE IF NOT EXISTS user_traffic_daily (
                day_ts INTEGER NOT NULL,
                username TEXT NOT NULL,
                bytes_down INTEGER NOT NULL DEFAULT 0,
                bytes_up INTEGER NOT NULL DEFAULT 0,
                active_seconds INTEGER NOT NULL DEFAULT 0,
                last_seen INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (day_ts, username)
            );
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_user_traffic_daily_user_day ON user_traffic_daily(username, day_ts);")
        conn.execute("""
            CREATE TABLE IF NOT EXISTS stats_meta (
                key TEXT PRIMARY KEY,
                value INTEGER NOT NULL
            );
        """)

def record_telemetry_entry(timestamp: int, node_id: str, data: dict):
    try:
        with sqlite3.connect(DB_PATH, timeout=5) as conn:
            online = 1 if data.get("online") else 0
            p50 = data.get("client_rtt_p50")
            anycast = data.get("anycast_ms")
            # For backward compatibility with node_pings: use client_rtt_p50 or anycast
            latency_compat = p50 if p50 is not None else anycast

            conn.execute(
                "INSERT INTO node_pings (timestamp, node_id, latency_ms, online) VALUES (?, ?, ?, ?)",
                (timestamp, node_id, latency_compat if online else None, online)
            )

            conn.execute("""
                INSERT INTO node_telemetry (
                    timestamp, node_id, online, active_sessions,
                    client_rtt_p50, client_rtt_p95, rtt_var,
                    retrans_rate_pct, anycast_ms, quality_score, status_label
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                timestamp,
                node_id,
                online,
                data.get("active_sessions", 0),
                p50,
                data.get("client_rtt_p95"),
                data.get("rtt_var"),
                data.get("retrans_rate_pct"),
                anycast,
                data.get("quality_score", 0),
                data.get("status_label", "Неизвестно")
            ))
    except Exception:
        pass

def rollup_completed_node_hours(conn, now_ts: int) -> int:
    """Idempotently summarize completed UTC hours before raw rows are pruned."""
    complete_before = (int(now_ts) // 3600) * 3600
    state = conn.execute(
        "SELECT value FROM stats_meta WHERE key = 'node_hourly_last_hour'"
    ).fetchone()

    if state is not None:
        start_hour = int(state[0]) + 3600
    else:
        first_telemetry = conn.execute("SELECT MIN(timestamp) FROM node_telemetry").fetchone()[0]
        first_ping = conn.execute("SELECT MIN(timestamp) FROM node_pings").fetchone()[0]
        first_values = [int(v) for v in (first_telemetry, first_ping) if v is not None]
        start_hour = (min(first_values) // 3600) * 3600 if first_values else complete_before

    if start_hour < complete_before:
        ping_rows = conn.execute("""
            SELECT CAST(timestamp / 3600 AS INTEGER) * 3600 AS hour_ts,
                   node_id, COUNT(*), SUM(COALESCE(online, 0)), AVG(latency_ms)
            FROM node_pings
            WHERE timestamp >= ? AND timestamp < ?
            GROUP BY hour_ts, node_id
        """, (start_hour, complete_before)).fetchall()
        telemetry_rows = conn.execute("""
            SELECT CAST(timestamp / 3600 AS INTEGER) * 3600 AS hour_ts,
                   node_id, COUNT(*), SUM(COALESCE(online, 0)),
                   AVG(client_rtt_p50), AVG(client_rtt_p95), MAX(client_rtt_p95),
                   AVG(rtt_var), AVG(retrans_rate_pct), AVG(anycast_ms),
                   AVG(quality_score), AVG(active_sessions)
            FROM node_telemetry
            WHERE timestamp >= ? AND timestamp < ?
            GROUP BY hour_ts, node_id
        """, (start_hour, complete_before)).fetchall()

        pings = {(int(r[0]), r[1]): r[2:] for r in ping_rows}
        telemetry = {(int(r[0]), r[1]): r[2:] for r in telemetry_rows}
        records = []
        for hour_ts, node_id in sorted(set(pings) | set(telemetry)):
            p = pings.get((hour_ts, node_id))
            t = telemetry.get((hour_ts, node_id))
            sample_count = int(t[0] if t else p[0])
            online_count = int(t[1] if t else p[1])
            uptime_pct = round(online_count * 100.0 / sample_count, 2) if sample_count else 0.0
            records.append((
                hour_ts, node_id, sample_count, online_count, uptime_pct,
                p[2] if p else None,
                *(t[2:] if t else (None, None, None, None, None, None, None, None))
            ))

        if records:
            conn.executemany("""
                INSERT INTO node_stats_hourly (
                    hour_ts, node_id, sample_count, online_count, uptime_pct, avg_ping_ms,
                    avg_client_rtt_p50, avg_client_rtt_p95, max_client_rtt_p95,
                    avg_rtt_var, avg_retrans_rate_pct, avg_anycast_ms,
                    avg_quality_score, avg_active_sessions
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(hour_ts, node_id) DO UPDATE SET
                    sample_count=excluded.sample_count,
                    online_count=excluded.online_count,
                    uptime_pct=excluded.uptime_pct,
                    avg_ping_ms=excluded.avg_ping_ms,
                    avg_client_rtt_p50=excluded.avg_client_rtt_p50,
                    avg_client_rtt_p95=excluded.avg_client_rtt_p95,
                    max_client_rtt_p95=excluded.max_client_rtt_p95,
                    avg_rtt_var=excluded.avg_rtt_var,
                    avg_retrans_rate_pct=excluded.avg_retrans_rate_pct,
                    avg_anycast_ms=excluded.avg_anycast_ms,
                    avg_quality_score=excluded.avg_quality_score,
                    avg_active_sessions=excluded.avg_active_sessions
            """, records)

    conn.execute("""
        INSERT INTO stats_meta (key, value) VALUES ('node_hourly_last_hour', ?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value
    """, (complete_before - 3600,))
    return len(records) if start_hour < complete_before else 0

def cleanup_metrics_db(now_ts: int) -> int:
    """Roll up complete hours, then prune raw and aggregated metric history."""
    with sqlite3.connect(DB_PATH, timeout=10) as conn:
        rolled_rows = rollup_completed_node_hours(conn, now_ts)
        conn.execute("DELETE FROM node_pings WHERE timestamp < ?", (now_ts - (7 * 86400),))
        conn.execute("DELETE FROM node_telemetry WHERE timestamp < ?", (now_ts - (7 * 86400),))
        conn.execute("DELETE FROM node_stats_hourly WHERE hour_ts < ?", (now_ts - (90 * 86400),))
        conn.execute("DELETE FROM user_traffic_daily WHERE day_ts < ?", (now_ts - (365 * 86400),))
    return rolled_rows

def parse_ss_and_anycast(raw_text: str) -> dict:
    parts = raw_text.split("===ANYCAST===")
    ss_part = parts[0] if len(parts) > 0 else ""
    anycast_part = parts[1] if len(parts) > 1 else ""

    # 1. Parse Anycast Ping (e.g. time=0.901 ms)
    anycast_ms = None
    m_any = re.search(r"time=([0-9.]+)\s*ms", anycast_part)
    if m_any:
        try:
            anycast_ms = round(float(m_any.group(1)), 2)
        except ValueError:
            pass

    # 2. Parse Kernel Sockets (ESTAB on :443)
    sockets = []
    lines = ss_part.splitlines()
    curr_sock = None

    for line in lines:
        line = line.strip()
        if not line:
            continue
        parts_line = line.split()
        if parts_line[0] in ("ESTAB", "ESTABLISHED"):
            if len(parts_line) >= 5:
                curr_sock = {
                    "local": parts_line[3],
                    "peer": parts_line[4],
                    "rtt": None,
                    "rttvar": None,
                    "bytes_sent": 0,
                    "bytes_retrans": 0,
                }
                sockets.append(curr_sock)
        elif curr_sock is not None and ("rtt:" in line or "bytes_sent:" in line or "bbr" in line):
            m_rtt = re.search(r"rtt:([0-9.]+)(?:/([0-9.]+))?", line)
            if m_rtt:
                curr_sock["rtt"] = float(m_rtt.group(1))
                if m_rtt.group(2):
                    curr_sock["rttvar"] = float(m_rtt.group(2))

            m_bs = re.search(r"bytes_sent:([0-9]+)", line)
            if m_bs:
                curr_sock["bytes_sent"] = int(m_bs.group(1))

            m_br = re.search(r"bytes_retrans:([0-9]+)", line)
            if m_br:
                curr_sock["bytes_retrans"] = int(m_br.group(1))

    active_sessions = len(sockets)
    rtts = [s["rtt"] for s in sockets if s["rtt"] is not None and s["rtt"] > 0]
    rttvars = [s["rttvar"] for s in sockets if s["rttvar"] is not None]

    total_sent = sum(s["bytes_sent"] for s in sockets)
    total_retrans = sum(s["bytes_retrans"] for s in sockets)

    retrans_rate = round((total_retrans / total_sent * 100), 2) if total_sent > 10000 else 0.0

    rtts.sort()
    if rtts:
        p50 = round(rtts[len(rtts) // 2], 1)
        p95_idx = min(len(rtts) - 1, int(len(rtts) * 0.95))
        p95 = round(rtts[p95_idx], 1)
    else:
        p50 = None
        p95 = None

    avg_var = round(sum(rttvars) / len(rttvars), 1) if rttvars else 0.0

    # Quality score (0 - 100)
    if active_sessions == 0:
        score = 100
        label = "Резерв"
    else:
        penalty = (retrans_rate * 3.5) + max(0, (avg_var - 15) * 0.4)
        score = max(5, min(100, int(100 - penalty)))
        if score >= 90:
            label = "Отличный"
        elif score >= 75:
            label = "Стабильный"
        elif score >= 50:
            label = "Шумный аплинк"
        else:
            label = "Деградация канала"

    return {
        "online": True,
        "active_sessions": active_sessions,
        "client_rtt_p50": p50,
        "client_rtt_p95": p95,
        "rtt_var": avg_var,
        "retrans_rate_pct": retrans_rate,
        "anycast_ms": anycast_ms,
        "quality_score": score,
        "status_label": label
    }

def poll_node(node: dict) -> dict:
    nid = node["id"]
    ip = str(node.get("ip", "")).strip()
    remote_cmd = "ss -ti sport = :443; echo '===ANYCAST==='; (ping -c 1 -W 1 1.1.1.1 2>/dev/null || true)"

    try:
        # Validate IP to prevent SSH argument injection (CWE-88)
        if ip not in LOCAL_IPS:
            ipaddress.ip_address(ip)
    except ValueError:
        return {
            "online": False,
            "active_sessions": 0,
            "client_rtt_p50": None,
            "client_rtt_p95": None,
            "rtt_var": 0.0,
            "retrans_rate_pct": 0.0,
            "anycast_ms": None,
            "quality_score": 0,
            "status_label": "invalid_ip",
            "latency_ms": None,
        }

    try:
        # Check if local node
        is_local = ip in LOCAL_IPS
        if is_local:
            res = subprocess.run(["bash", "-c", remote_cmd], capture_output=True, text=True, timeout=5)
        else:
            ssh_cmd = [
                "ssh",
                "-i", str(CLUSTER_SSH_KEY),
                "-p", SSH_PORT,
                "-o", "StrictHostKeyChecking=no",
                "-o", "ConnectTimeout=3",
                "--",
                f"{SSH_USER}@{ip}",
                remote_cmd
            ]
            res = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=7)

        if (res.returncode == 0 or "===ANYCAST===" in (res.stdout or "")) and res.stdout:
            parsed = parse_ss_and_anycast(res.stdout)
            parsed["latency_ms"] = parsed["client_rtt_p50"] if parsed["client_rtt_p50"] else parsed["anycast_ms"]
            return parsed
        else:
            return {
                "online": False,
                "active_sessions": 0,
                "client_rtt_p50": None,
                "client_rtt_p95": None,
                "rtt_var": 0.0,
                "retrans_rate_pct": 0.0,
                "anycast_ms": None,
                "quality_score": 0,
                "status_label": "Недоступен",
                "latency_ms": None,
                "error": res.stderr[:100] if res.stderr else "Non-zero exit"
            }
    except Exception as e:
        return {
            "online": False,
            "active_sessions": 0,
            "client_rtt_p50": None,
            "client_rtt_p95": None,
            "rtt_var": 0.0,
            "retrans_rate_pct": 0.0,
            "anycast_ms": None,
            "quality_score": 0,
            "status_label": "Таймаут",
            "latency_ms": None,
            "error": str(e)
        }

def metrics_collector_loop():
    """Polls all cluster nodes every 15 seconds in parallel (Stealth & Zero Overhead)."""
    global _latest_node_status
    time.sleep(2)
    # Run one retention/backfill pass on startup, then once per hour.
    clean_counter = 239

    while True:
        ts = int(time.time())
        results = {}

        # Parallel polling across nodes (completes in ~0.5s)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
            future_to_node = {ex.submit(poll_node, n): n for n in get_nodes()}
            for future in concurrent.futures.as_completed(future_to_node):
                n = future_to_node[future]
                nid = n["id"]
                try:
                    stats = future.result()
                except Exception as e:
                    stats = {
                        "online": False,
                        "active_sessions": 0,
                        "client_rtt_p50": None,
                        "client_rtt_p95": None,
                        "rtt_var": 0.0,
                        "retrans_rate_pct": 0.0,
                        "anycast_ms": None,
                        "quality_score": 0,
                        "status_label": "Ошибка",
                        "latency_ms": None
                    }

                stats["id"] = nid
                stats["name"] = n["name"]
                stats["dc"] = n["dc"]
                stats["ip"] = n["ip"]
                results[nid] = stats

                # Record to SQLite
                record_telemetry_entry(ts, nid, stats)

        with _status_lock:
            _latest_node_status = results

        # Cleanup old data (> 7 days) every hour
        clean_counter += 1
        if clean_counter >= 240:  # 240 * 15s = 3600s
            clean_counter = 0
            try:
                rolled_rows = cleanup_metrics_db(ts)
                if rolled_rows:
                    print(f"[metrics] rolled up {rolled_rows} node-hour rows", flush=True)
            except Exception as e:
                print(f"[metrics] rollup/retention failed: {e}", flush=True)

        time.sleep(15)

def get_node_status() -> list:
    """Returns the latest in-memory telemetry status for all nodes."""
    with _status_lock:
        cached = _latest_node_status.copy()

    results = []
    for node in get_nodes():
        nid = node["id"]
        if nid in cached:
            results.append(cached[nid])
        else:
            results.append({
                "id": nid,
                "name": node["name"],
                "dc": node["dc"],
                "ip": node["ip"],
                "online": True,
                "active_sessions": 0,
                "client_rtt_p50": None,
                "client_rtt_p95": None,
                "rtt_var": 0.0,
                "retrans_rate_pct": 0.0,
                "anycast_ms": None,
                "quality_score": 100,
                "status_label": "Опрос...",
                "latency_ms": None
            })
    return results

def get_node_rollup_history(hours: int = 720, max_points: int = 80) -> dict:
    """Serve long ranges from hourly aggregates instead of scanning raw samples."""
    hours = max(169, min(int(hours), 2160))
    max_points = max(20, min(int(max_points), 500))
    since = int(time.time()) - (hours * 3600)
    nodes = get_nodes()
    node_ids = [n["id"] for n in nodes]
    if not node_ids:
        return {"history": [], "hours": hours, "summary": {}}

    placeholders = ",".join("?" for _ in node_ids)
    try:
        with sqlite3.connect(DB_PATH, timeout=5) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(f"""
                SELECT hour_ts, node_id, sample_count, online_count, uptime_pct,
                       avg_ping_ms, avg_client_rtt_p50, avg_client_rtt_p95,
                       avg_rtt_var, avg_retrans_rate_pct, avg_anycast_ms,
                       avg_quality_score, avg_active_sessions
                FROM node_stats_hourly
                WHERE hour_ts >= ? AND node_id IN ({placeholders})
                ORDER BY hour_ts ASC
            """, (since, *node_ids)).fetchall()

        if not rows:
            return {"history": [], "hours": hours, "summary": {}}

        bucket_hours = max(1, math.ceil(hours / max_points))
        bucket_size = bucket_hours * 3600
        bucket_values = {}
        totals = {nid: {
            "samples": 0, "online": 0, "last_sessions": 0,
            "last_hour": 0,
            "rtt": [0.0, 0], "retrans": [0.0, 0],
            "score": [0.0, 0], "anycast": [0.0, 0], "jitter": [0.0, 0]
        } for nid in node_ids}

        def add_bucket(bucket, metric, node_id, value, weight):
            if value is None or weight <= 0:
                return
            pair = bucket.setdefault(metric, {}).setdefault(node_id, [0.0, 0])
            pair[0] += float(value) * weight
            pair[1] += weight

        for row in rows:
            nid = row["node_id"]
            if nid not in totals:
                continue
            weight = max(0, int(row["sample_count"] or 0))
            if not weight:
                continue
            online = max(0, int(row["online_count"] or 0))
            stat = totals[nid]
            stat["samples"] += weight
            stat["online"] += online
            stat["last_sessions"] = row["avg_active_sessions"] or 0
            stat["last_hour"] = row["hour_ts"]

            values = {
                "rtt": row["avg_client_rtt_p50"],
                "retrans": row["avg_retrans_rate_pct"],
                "score": row["avg_quality_score"],
                "anycast": row["avg_anycast_ms"],
                "jitter": row["avg_rtt_var"]
            }
            for key, value in values.items():
                if value is not None:
                    stat[key][0] += float(value) * weight
                    stat[key][1] += weight

            bucket_ts = (int(row["hour_ts"]) // bucket_size) * bucket_size
            bucket = bucket_values.setdefault(bucket_ts, {})
            ping_value = row["avg_client_rtt_p50"]
            if ping_value is None:
                ping_value = row["avg_ping_ms"]
            add_bucket(bucket, "pings", nid, ping_value if ping_value is not None else row["avg_anycast_ms"], weight)
            add_bucket(bucket, "rtt", nid, row["avg_client_rtt_p50"], weight)
            add_bucket(bucket, "retrans", nid, row["avg_retrans_rate_pct"], weight)
            add_bucket(bucket, "score", nid, row["avg_quality_score"], weight)
            add_bucket(bucket, "anycast", nid, row["avg_anycast_ms"], weight)
            add_bucket(bucket, "sessions", nid, row["avg_active_sessions"], weight)

        chart_data = []
        for bucket_ts in sorted(bucket_values):
            bucket = bucket_values[bucket_ts]
            entry = {"timestamp": bucket_ts, "pings": {}, "rtt": {}, "retrans": {}, "score": {}, "anycast": {}, "sessions": {}}
            for nid in node_ids:
                for metric in ("pings", "rtt", "retrans", "score", "anycast", "sessions"):
                    pair = bucket.get(metric, {}).get(nid)
                    value = pair[0] / pair[1] if pair and pair[1] else None
                    if metric in ("pings", "rtt", "anycast") and value is not None:
                        value = round(value, 2 if metric == "anycast" else 1)
                    elif metric == "retrans" and value is not None:
                        value = round(value, 2)
                    elif metric in ("score", "sessions") and value is not None:
                        value = int(round(value))
                    entry[metric][nid] = value
            chart_data.append(entry)

        summary = {}
        for node in nodes:
            nid = node["id"]
            stat = totals[nid]
            samples = stat["samples"]
            online = stat["online"]
            def average(key):
                total, weight = stat[key]
                return total / weight if weight else None
            avg_rtt = average("rtt")
            avg_retrans = average("retrans")
            avg_score = average("score")
            avg_anycast = average("anycast")
            avg_jitter = average("jitter")
            score = int(round(avg_score)) if avg_score is not None else 100
            label = "Отличный" if score >= 90 else "Стабильный" if score >= 75 else "Шумный аплинк" if score >= 50 else "Деградация канала"
            summary[nid] = {
                "name": node["name"], "dc": node["dc"],
                "avg_ms": round(avg_rtt, 1) if avg_rtt is not None else None,
                "client_rtt_p50": round(avg_rtt, 1) if avg_rtt is not None else None,
                "retrans_rate_pct": round(avg_retrans, 2) if avg_retrans is not None else 0.0,
                "quality_score": score, "status_label": label,
                "anycast_ms": round(avg_anycast, 2) if avg_anycast is not None else None,
                "jitter_ms": round(avg_jitter, 1) if avg_jitter is not None else 0.0,
                "packet_loss_pct": round((samples - online) * 100.0 / samples, 1) if samples else 0.0,
                "active_sessions": int(round(stat["last_sessions"])),
                "total_checks": samples
            }
        return {"history": chart_data, "hours": hours, "summary": summary, "source": "hourly"}
    except Exception as e:
        return {"history": [], "hours": hours, "summary": {}, "error": str(e)}

def get_pings_history(hours: int = 24, max_points: int = 80) -> dict:
    hours = max(1, min(int(hours), 2160))
    max_points = max(20, min(int(max_points), 500))
    if hours > 168:
        return get_node_rollup_history(hours, max_points)
    since = int(time.time()) - (hours * 3600)
    try:
        with sqlite3.connect(DB_PATH, timeout=5) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute("""
                SELECT timestamp, node_id, online, active_sessions,
                       client_rtt_p50, client_rtt_p95, rtt_var,
                       retrans_rate_pct, anycast_ms, quality_score, status_label
                FROM node_telemetry
                WHERE timestamp >= ?
                ORDER BY timestamp ASC
            """, (since,)).fetchall()

        if not rows:
            # Fallback to node_pings if node_telemetry has no rows yet
            rows_old = conn.execute(
                "SELECT timestamp, node_id, latency_ms, online FROM node_pings WHERE timestamp >= ? ORDER BY timestamp ASC",
                (since,)
            ).fetchall()
            if not rows_old:
                return {"history": [], "hours": hours, "summary": {}}

        total_time = int(time.time()) - since
        bucket_size = max(5, total_time // max_points)

        buckets = {}
        node_stats = {n["id"]: {
            "rtts": [], "retrans": [], "scores": [], "anycasts": [],
            "tot_checks": 0, "onl_checks": 0, "sessions": []
        } for n in get_nodes()}

        for r in rows:
            nid = r["node_id"]
            if nid not in node_stats:
                continue

            node_stats[nid]["tot_checks"] += 1
            if r["online"]:
                node_stats[nid]["onl_checks"] += 1
            if r["client_rtt_p50"] is not None:
                node_stats[nid]["rtts"].append(r["client_rtt_p50"])
            if r["retrans_rate_pct"] is not None:
                node_stats[nid]["retrans"].append(r["retrans_rate_pct"])
            if r["quality_score"] is not None:
                node_stats[nid]["scores"].append(r["quality_score"])
            if r["anycast_ms"] is not None:
                node_stats[nid]["anycasts"].append(r["anycast_ms"])
            if r["active_sessions"] is not None:
                node_stats[nid]["sessions"].append(r["active_sessions"])

            b_ts = (r["timestamp"] // bucket_size) * bucket_size
            if b_ts not in buckets:
                buckets[b_ts] = {
                    "pings": {}, "rtt": {}, "retrans": {},
                    "score": {}, "anycast": {}, "sessions": {}
                }

            val_rtt = r["client_rtt_p50"]
            val_any = r["anycast_ms"]
            pings_compat = val_rtt if val_rtt is not None else val_any

            if pings_compat is not None:
                buckets[b_ts]["pings"].setdefault(nid, []).append(pings_compat)
            if val_rtt is not None:
                buckets[b_ts]["rtt"].setdefault(nid, []).append(val_rtt)
            if r["retrans_rate_pct"] is not None:
                buckets[b_ts]["retrans"].setdefault(nid, []).append(r["retrans_rate_pct"])
            if r["quality_score"] is not None:
                buckets[b_ts]["score"].setdefault(nid, []).append(r["quality_score"])
            if val_any is not None:
                buckets[b_ts]["anycast"].setdefault(nid, []).append(val_any)
            if r["active_sessions"] is not None:
                buckets[b_ts]["sessions"].setdefault(nid, []).append(r["active_sessions"])

        chart_data = []
        for b_ts in sorted(buckets.keys()):
            entry = {
                "timestamp": b_ts,
                "pings": {}, "rtt": {}, "retrans": {},
                "score": {}, "anycast": {}, "sessions": {}
            }
            for n in get_nodes():
                n_id = n["id"]
                b = buckets[b_ts]
                entry["pings"][n_id] = round(sum(b["pings"][n_id]) / len(b["pings"][n_id]), 1) if n_id in b["pings"] else None
                entry["rtt"][n_id] = round(sum(b["rtt"][n_id]) / len(b["rtt"][n_id]), 1) if n_id in b["rtt"] else None
                entry["retrans"][n_id] = round(sum(b["retrans"][n_id]) / len(b["retrans"][n_id]), 2) if n_id in b["retrans"] else None
                entry["score"][n_id] = int(round(sum(b["score"][n_id]) / len(b["score"][n_id]))) if n_id in b["score"] else None
                entry["anycast"][n_id] = round(sum(b["anycast"][n_id]) / len(b["anycast"][n_id]), 2) if n_id in b["anycast"] else None
                entry["sessions"][n_id] = int(round(sum(b["sessions"][n_id]) / len(b["sessions"][n_id]))) if n_id in b["sessions"] else None
            chart_data.append(entry)

        summary = {}
        for n in get_nodes():
            nid = n["id"]
            ns = node_stats[nid]
            tot = ns["tot_checks"]
            onl = ns["onl_checks"]

            avg_rtt = round(sum(ns["rtts"]) / len(ns["rtts"]), 1) if ns["rtts"] else None
            avg_retrans = round(sum(ns["retrans"]) / len(ns["retrans"]), 2) if ns["retrans"] else 0.0
            avg_score = int(round(sum(ns["scores"]) / len(ns["scores"]))) if ns["scores"] else 100
            avg_anycast = round(sum(ns["anycasts"]) / len(ns["anycasts"]), 2) if ns["anycasts"] else None
            cur_sessions = ns["sessions"][-1] if ns["sessions"] else 0

            # Jitter
            if len(ns["rtts"]) > 1 and avg_rtt:
                variance = sum((x - avg_rtt) ** 2 for x in ns["rtts"]) / len(ns["rtts"])
                jitter = round(math.sqrt(variance), 1)
            else:
                jitter = 0.0

            loss_pct = round(((tot - onl) / tot * 100), 1) if tot > 0 else 0.0

            if avg_score >= 90:
                slabel = "Отличный"
            elif avg_score >= 75:
                slabel = "Стабильный"
            elif avg_score >= 50:
                slabel = "Шумный аплинк"
            else:
                slabel = "Деградация канала"

            summary[nid] = {
                "name": n["name"],
                "dc": n["dc"],
                "avg_ms": avg_rtt,
                "client_rtt_p50": avg_rtt,
                "retrans_rate_pct": avg_retrans,
                "quality_score": avg_score,
                "status_label": slabel,
                "anycast_ms": avg_anycast,
                "jitter_ms": jitter,
                "packet_loss_pct": loss_pct,
                "active_sessions": cur_sessions,
                "total_checks": tot
            }

        return {"history": chart_data, "hours": hours, "summary": summary}
    except Exception as e:
        return {"history": [], "hours": hours, "summary": {}, "error": str(e)}

# --- XRAY TRAFFIC & STATS COLLECTOR ---

_xray_last_raw = {}
_xray_stats_lock = threading.Lock()

def format_bytes(size_bytes: int) -> str:
    if not size_bytes or size_bytes <= 0:
        return "0 B"
    size_name = ("B", "KB", "MB", "GB", "TB")
    i = int(math.floor(math.log(size_bytes, 1024)))
    p = math.pow(1024, i)
    s = round(size_bytes / p, 2)
    return f"{s} {size_name[i]}"

def xray_stats_collector_loop():
    """Runs in background every 10 seconds, queries local Xray API (127.0.0.1:10085)."""
    time.sleep(3)
    last_online_sample_ts = None
    while True:
        try:
            proc = subprocess.run(
                ["xray", "api", "statsquery", "--server=127.0.0.1:10085", "-pattern", ""],
                capture_output=True, text=True, timeout=8
            )
            if proc.returncode == 0 and proc.stdout.strip():
                data = json.loads(proc.stdout)
                stats_list = data.get("stat", [])
                now_ts = int(time.time())

                user_deltas = {}
                with _xray_stats_lock:
                    for item in stats_list:
                        name = item.get("name", "")
                        val = int(item.get("value", 0))
                        parts = name.split(">>>")
                        if len(parts) >= 4 and parts[0] == "user" and parts[2] == "traffic":
                            uname = parts[1]
                            direction = parts[3]

                            if uname not in user_deltas:
                                user_deltas[uname] = {"down": 0, "up": 0}

                            prev = _xray_last_raw.get((uname, direction))
                            if prev is None:
                                delta = 0
                            elif val >= prev:
                                delta = val - prev
                            else:
                                delta = val

                            _xray_last_raw[(uname, direction)] = val

                            if direction == "downlink":
                                user_deltas[uname]["down"] += delta
                            elif direction == "uplink":
                                user_deltas[uname]["up"] += delta

                online_users = set()
                online_query_ok = False
                try:
                    proc_onl = subprocess.run(
                        ["xray", "api", "statsgetallonlineusers", "--server=127.0.0.1:10085"],
                        capture_output=True, text=True, timeout=5
                    )
                    if proc_onl.returncode == 0 and proc_onl.stdout.strip():
                        onl_data = json.loads(proc_onl.stdout)
                        if isinstance(onl_data, list):
                            online_users = set(onl_data)
                            online_query_ok = True
                        elif isinstance(onl_data, dict):
                            online_users = set(onl_data.get("users", []))
                            online_query_ok = True
                except Exception:
                    pass

                for uname, d in user_deltas.items():
                    if d["down"] > 0 or d["up"] > 0:
                        online_users.add(uname)

                # Estimate active time from successful polls; cap gaps so pauses do not overcount.
                active_sample_seconds = 0
                if online_query_ok:
                    if last_online_sample_ts is not None:
                        active_sample_seconds = max(0, min(now_ts - last_online_sample_ts, 30))
                    last_online_sample_ts = now_ts

                traffic_users = set(user_deltas) | online_users
                day_ts = (now_ts // 86400) * 86400  # UTC epoch-day bucket
                with sqlite3.connect(DB_PATH, timeout=5) as conn:
                    for uname in traffic_users:
                        d = user_deltas.get(uname, {"down": 0, "up": 0})
                        is_onl = 1 if uname in online_users else 0
                        last_seen = now_ts if (is_onl or d["down"] > 0 or d["up"] > 0) else 0
                        conn.execute("""
                            INSERT INTO user_xray_traffic (username, bytes_down, bytes_up, last_seen, is_online, sessions_count)
                            VALUES (?, ?, ?, ?, ?, ?)
                            ON CONFLICT(username) DO UPDATE SET
                                bytes_down = bytes_down + excluded.bytes_down,
                                bytes_up = bytes_up + excluded.bytes_up,
                                last_seen = CASE WHEN excluded.is_online = 1 OR excluded.bytes_down > 0 OR excluded.bytes_up > 0 THEN excluded.last_seen ELSE last_seen END,
                                is_online = excluded.is_online,
                                sessions_count = excluded.sessions_count;
                        """, (
                            uname, d["down"], d["up"], last_seen, is_onl, 1 if is_onl else 0
                        ))

                        active_seconds = active_sample_seconds if is_onl else 0
                        if d["down"] > 0 or d["up"] > 0 or active_seconds > 0:
                            conn.execute("""
                                INSERT INTO user_traffic_daily (
                                    day_ts, username, bytes_down, bytes_up, active_seconds, last_seen
                                ) VALUES (?, ?, ?, ?, ?, ?)
                                ON CONFLICT(day_ts, username) DO UPDATE SET
                                    bytes_down = user_traffic_daily.bytes_down + excluded.bytes_down,
                                    bytes_up = user_traffic_daily.bytes_up + excluded.bytes_up,
                                    active_seconds = user_traffic_daily.active_seconds + excluded.active_seconds,
                                    last_seen = MAX(user_traffic_daily.last_seen, excluded.last_seen)
                            """, (
                                day_ts, uname, d["down"], d["up"], active_seconds, last_seen
                            ))

                    all_users = get_users_list()
                    for u in all_users:
                        if u not in online_users:
                            conn.execute("UPDATE user_xray_traffic SET is_online = 0 WHERE username = ?", (u,))

        except Exception:
            pass

        time.sleep(10)

def get_xray_stats_overview() -> dict:
    try:
        with sqlite3.connect(DB_PATH, timeout=5) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute("SELECT username, bytes_down, bytes_up, last_seen, is_online FROM user_xray_traffic").fetchall()

        total_down = sum(r["bytes_down"] for r in rows)
        total_up = sum(r["bytes_up"] for r in rows)
        online_count = sum(1 for r in rows if r["is_online"])

        return {
            "total_down_bytes": total_down,
            "total_up_bytes": total_up,
            "total_bytes": total_down + total_up,
            "total_formatted": format_bytes(total_down + total_up),
            "down_formatted": format_bytes(total_down),
            "up_formatted": format_bytes(total_up),
            "online_count": online_count,
            "total_tracked": len(rows)
        }
    except Exception as e:
        return {
            "total_bytes": 0,
            "total_formatted": "0 B",
            "down_formatted": "0 B",
            "up_formatted": "0 B",
            "online_count": 0,
            "error": str(e)
        }

def get_user_xray_traffic(username: str) -> dict:
    try:
        with sqlite3.connect(DB_PATH, timeout=5) as conn:
            conn.row_factory = sqlite3.Row
            r = conn.execute("SELECT bytes_down, bytes_up, last_seen, is_online, sessions_count FROM user_xray_traffic WHERE username = ?", (username,)).fetchone()
        if r:
            b_down = r["bytes_down"]
            b_up = r["bytes_up"]
            b_tot = b_down + b_up
            return {
                "bytes_down": b_down,
                "bytes_up": b_up,
                "bytes_total": b_tot,
                "total_formatted": format_bytes(b_tot),
                "down_formatted": format_bytes(b_down),
                "up_formatted": format_bytes(b_up),
                "is_online": bool(r["is_online"]),
                "sessions_count": r["sessions_count"],
                "last_seen_vpn": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(r["last_seen"])) if r["last_seen"] > 0 else None
            }
    except Exception:
        pass
    return {
        "bytes_down": 0,
        "bytes_up": 0,
        "bytes_total": 0,
        "total_formatted": "0 B",
        "down_formatted": "0 B",
        "up_formatted": "0 B",
        "is_online": False,
        "sessions_count": 0,
        "last_seen_vpn": None
    }

def _bounded_history_days(value, default=7, maximum=365):
    try:
        days = int(value)
    except (TypeError, ValueError):
        days = default
    return max(1, min(days, maximum))


def get_users_traffic_period(days=7) -> dict:
    """Return bounded per-user Xray traffic for recent UTC day buckets."""
    days = _bounded_history_days(days, default=7, maximum=365)
    now_ts = int(time.time())
    today_ts = (now_ts // 86400) * 86400
    start_day = today_ts - ((days - 1) * 86400)
    try:
        with sqlite3.connect(DB_PATH, timeout=5) as conn:
            conn.row_factory = sqlite3.Row
            daily_rows = conn.execute("""
                SELECT username, SUM(bytes_down) AS bytes_down,
                       SUM(bytes_up) AS bytes_up, SUM(active_seconds) AS active_seconds,
                       MAX(last_seen) AS period_last_seen
                FROM user_traffic_daily
                WHERE day_ts >= ?
                GROUP BY username
            """, (start_day,)).fetchall()
            current_rows = conn.execute("""
                SELECT username, bytes_down, bytes_up, last_seen, is_online
                FROM user_xray_traffic
            """).fetchall()
            first_available_day = conn.execute(
                "SELECT MIN(day_ts) FROM user_traffic_daily"
            ).fetchone()[0]

        daily = {r["username"]: r for r in daily_rows}
        current = {r["username"]: r for r in current_rows}
        users = []
        for username in get_users_list():
            d = daily.get(username)
            c = current.get(username)
            down = int(d["bytes_down"] or 0) if d else 0
            up = int(d["bytes_up"] or 0) if d else 0
            active_seconds = int(d["active_seconds"] or 0) if d else 0
            current_down = int(c["bytes_down"] or 0) if c else 0
            current_up = int(c["bytes_up"] or 0) if c else 0
            last_seen = int(c["last_seen"] or 0) if c else 0
            if not last_seen and d:
                last_seen = int(d["period_last_seen"] or 0)
            users.append({
                "username": username,
                "bytes_down": down,
                "bytes_up": up,
                "bytes_total": down + up,
                "down_formatted": format_bytes(down),
                "up_formatted": format_bytes(up),
                "total_formatted": format_bytes(down + up),
                "active_seconds": active_seconds,
                "active_minutes": round(active_seconds / 60, 1),
                "current_total_bytes": current_down + current_up,
                "is_online": bool(c["is_online"]) if c else False,
                "last_seen": last_seen or None,
                "last_seen_vpn": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(last_seen)) if last_seen else None
            })

        users.sort(key=lambda u: (-u["bytes_total"], u["username"].lower()))
        total_down = sum(u["bytes_down"] for u in users)
        total_up = sum(u["bytes_up"] for u in users)
        active_users = sum(1 for u in users if u["bytes_total"] > 0 or u["active_seconds"] > 0)
        online_users = sum(1 for u in users if u["is_online"])
        return {
            "days": days,
            "start_day": start_day,
            "history_available_from": int(first_available_day) if first_available_day is not None else None,
            "generated_at": now_ts,
            "total_users": len(users),
            "active_users": active_users,
            "online_users": online_users,
            "bytes_down": total_down,
            "bytes_up": total_up,
            "bytes_total": total_down + total_up,
            "down_formatted": format_bytes(total_down),
            "up_formatted": format_bytes(total_up),
            "total_formatted": format_bytes(total_down + total_up),
            "active_seconds": sum(u["active_seconds"] for u in users),
            "users": users
        }
    except Exception as e:
        return {"days": days, "users": [], "total_users": 0, "error": str(e)}


def get_user_traffic_history(username: str, days=30) -> dict:
    """Return a zero-filled daily series; collection starts at feature rollout."""
    days = _bounded_history_days(days, default=30, maximum=365)
    now_ts = int(time.time())
    today_ts = (now_ts // 86400) * 86400
    start_day = today_ts - ((days - 1) * 86400)
    with sqlite3.connect(DB_PATH, timeout=5) as conn:
        rows = conn.execute("""
            SELECT day_ts, bytes_down, bytes_up, active_seconds, last_seen
            FROM user_traffic_daily
            WHERE username = ? AND day_ts >= ?
            ORDER BY day_ts
        """, (username, start_day)).fetchall()
        first_day = conn.execute(
            "SELECT MIN(day_ts) FROM user_traffic_daily WHERE username = ?", (username,)
        ).fetchone()[0]
    by_day = {int(r[0]): r for r in rows}
    history = []
    for offset in range(days):
        day_ts = start_day + offset * 86400
        r = by_day.get(day_ts)
        down = int(r[1] or 0) if r else 0
        up = int(r[2] or 0) if r else 0
        history.append({
            "day_ts": day_ts,
            "bytes_down": down,
            "bytes_up": up,
            "bytes_total": down + up,
            "active_seconds": int(r[3] or 0) if r else 0,
            "last_seen": int(r[4] or 0) if r else 0
        })
    return {
        "username": username,
        "days": days,
        "history_available_from": int(first_day) if first_day is not None else None,
        "history": history
    }


# --- USER PASSWORDS / PINs MANAGEMENT ---

_pin_rate_lock = threading.Lock()
_pin_failed_attempts = {}

def is_pin_rate_limited(ip: str, username: str) -> bool:
    now = time.time()
    key = (str(ip).strip(), str(username).strip().lower())
    with _pin_rate_lock:
        attempts = [t for t in _pin_failed_attempts.get(key, []) if now - t < 300]
        _pin_failed_attempts[key] = attempts
        return len(attempts) >= 5

def record_failed_pin_attempt(ip: str, username: str):
    now = time.time()
    key = (str(ip).strip(), str(username).strip().lower())
    with _pin_rate_lock:
        attempts = [t for t in _pin_failed_attempts.get(key, []) if now - t < 300]
        attempts.append(now)
        _pin_failed_attempts[key] = attempts

def clear_pin_rate_limit(ip: str, username: str):
    key = (str(ip).strip(), str(username).strip().lower())
    with _pin_rate_lock:
        _pin_failed_attempts.pop(key, None)

def hash_pin(pin: str) -> str:
    pin = str(pin).strip()
    salt = secrets.token_hex(16)
    key = hashlib.pbkdf2_hmac("sha256", pin.encode("utf-8"), salt.encode("utf-8"), 100000)
    return f"pbkdf2:sha256:100000${salt}${key.hex()}"

def verify_hash(pin: str, stored_hash: str) -> bool:
    if not stored_hash or not pin:
        return False
    pin = str(pin).strip()
    # Backward compatibility with legacy plaintext passwords
    if not stored_hash.startswith("pbkdf2:sha256:"):
        return hmac.compare_digest(stored_hash.strip().encode("utf-8"), pin.encode("utf-8"))
    try:
        parts = stored_hash.split("$")
        if len(parts) != 3:
            return False
        iterations = int(parts[0].split(":")[-1])
        salt = parts[1].encode("utf-8")
        expected_key = parts[2]
        key = hashlib.pbkdf2_hmac("sha256", pin.encode("utf-8"), salt, iterations)
        return hmac.compare_digest(key.hex(), expected_key)
    except Exception:
        return False

def load_passwords() -> dict:
    if not PASSWORDS_FILE.exists():
        return {}
    try:
        return json.loads(PASSWORDS_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {}

def save_passwords(data: dict):
    PASSWORDS_FILE.parent.mkdir(parents=True, exist_ok=True)
    PASSWORDS_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        PASSWORDS_FILE.chmod(0o600)
    except Exception:
        pass

def get_user_pin(username: str) -> str:
    pwds = load_passwords()
    if username in pwds and pwds[username]:
        val = str(pwds[username]).strip()
        # If legacy plaintext, return so admin can see it; if hashed, return placeholder
        if not val.startswith("pbkdf2:sha256:"):
            return val
        return "••••"
    # Cryptographically secure random 4-digit PIN (CWE-330/CWE-338 fix)
    pin = str(secrets.randbelow(9000) + 1000)
    set_user_pin(username, pin)
    return pin

def set_user_pin(username: str, pin: str):
    username = username.strip()
    pin = str(pin).strip()
    if not pin:
        raise ValueError("Пароль/PIN не может быть пустым")
    pwds = load_passwords()
    # Store cryptographic salted hash (CWE-256 fix)
    pwds[username] = hash_pin(pin)
    save_passwords(pwds)

def get_user_uuid(username: str) -> str:
    try:
        users_file = f"{ETC_DIR}/users.json"
        if os.path.exists(users_file):
            import json
            with open(users_file, "r") as f:
                data = json.load(f)
                if username in data:
                    return data[username]
                for k, v in data.items():
                    if k.lower() == username.lower():
                        return v
    except Exception:
        pass
    return ""

def verify_user_pin(username: str, pin: str) -> bool:
    username = username.strip()
    pin = str(pin).strip()
    if not pin or not username:
        return False

    pwds = load_passwords()

    matched_key = None
    if username in pwds and verify_hash(pin, pwds[username]):
        matched_key = username
    else:
        for k, v in pwds.items():
            if k.lower() == username.lower() and verify_hash(pin, v):
                matched_key = k
                break

    if matched_key:
        # Transparent upgrade to salted hash on first successful login
        if not pwds[matched_key].startswith("pbkdf2:sha256:"):
            pwds[matched_key] = hash_pin(pin)
            save_passwords(pwds)
        return True

    return False

# --- SYSTEM MEMORY & CHANGELOG ---

def get_system_memory() -> dict:
    mem = ""
    chlog = ""
    if SYSTEM_MEMORY_FILE.exists():
        mem = SYSTEM_MEMORY_FILE.read_text(encoding="utf-8", errors="ignore")
    if CHANGELOG_FILE.exists():
        chlog = CHANGELOG_FILE.read_text(encoding="utf-8", errors="ignore")
    return {"memory": mem, "changelog": chlog}

def log_system_memory(description: str, author: str = "agent", category: str = "OPERATIONS", files: str = "N/A", rollback: str = "N/A") -> bool:
    CHANGELOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime())
    date_header = time.strftime("%Y-%m-%d", time.gmtime())

    # Sanitize inputs against Stored XSS
    description = html.escape(str(description).strip())
    author = html.escape(str(author).strip())
    category = html.escape(str(category).strip())
    files = html.escape(str(files).strip())
    rollback = html.escape(str(rollback).strip())

    current_content = ""
    if CHANGELOG_FILE.exists():
        current_content = CHANGELOG_FILE.read_text(encoding="utf-8", errors="ignore")
    else:
        current_content = "# Журнал изменений VPN-Davida (Changelog & Decision Log)\n\n"

    entry = f"- **[{ts}] | {author} | {category}**\n  - {description}\n  - **Затронутые файлы:** {files}\n  - **Точка отката:** {rollback}\n"

    if f"## {date_header}" not in current_content:
        entry = f"\n## {date_header}\n\n{entry}"
    else:
        entry = f"\n{entry}"

    CHANGELOG_FILE.write_text(current_content + entry, encoding="utf-8")
    return True

# --- UTILITIES ---

def create_token(data: str) -> str:
    timestamp = str(int(time.time()))
    payload = f"{data}:{timestamp}"
    sig = hmac.new(SECRET_KEY, payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}:{sig}"

def verify_token(token: str, required_role: str = "admin") -> bool:
    if not token:
        return False
    parts = token.split(":")
    if len(parts) != 3:
        return False
    data, timestamp_str, sig = parts
    # CWE-347 fix: Validate role/user payload
    if required_role and data != required_role:
        return False
    try:
        ts = int(timestamp_str)
        if time.time() - ts > SESSION_DURATION_SEC:
            return False
    except ValueError:
        return False
    expected_payload = f"{data}:{timestamp_str}"
    expected_sig = hmac.new(SECRET_KEY, expected_payload.encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(sig, expected_sig)

def get_users_list() -> list:
    if not USERS_FILE.exists():
        return []
    lines = USERS_FILE.read_text(encoding="utf-8").splitlines()
    users = [u.strip() for u in lines if u.strip() and not u.startswith("#")]
    return sorted(list(set(users)))

# --- LOG CACHING & PARSER ---

import gzip
import glob

_log_cache = {
    "mtime": 0,
    "size": 0,
    "checked_at": 0.0,
    "stats": {}
}
_LOG_STATS_CACHE_TTL_SEC = 15

def parse_all_users_stats():
    global _log_cache
    now = time.monotonic()
    if now - _log_cache.get("checked_at", 0.0) < _LOG_STATS_CACHE_TTL_SEC:
        return _log_cache.get("stats", {})

    log_files = sorted(glob.glob(f"{LOG_BASENAME}*"))
    if not log_files:
        _log_cache.update({"checked_at": now, "stats": {}})
        return {}

    try:
        active_stat = LOG_FILE.stat() if LOG_FILE.exists() else None
        if active_stat and active_stat.st_mtime == _log_cache.get("mtime") and active_stat.st_size == _log_cache.get("size"):
            _log_cache["checked_at"] = now
            return _log_cache["stats"]

        users = get_users_list()
        user_stats = {}
        for u in users:
            user_stats[u] = {
                "sub_downloads": 0,
                "page_views": 0,
                "ips": {},
                "uas": {},
                "last_seen": None
            }

        for lf in sorted(log_files, key=lambda x: os.path.getmtime(x)):
            try:
                if lf.endswith(".gz"):
                    open_fn = lambda p: gzip.open(p, "rt", encoding="utf-8", errors="replace")
                else:
                    open_fn = lambda p: open(p, "r", encoding="utf-8", errors="replace")

                with open_fn(lf) as f:
                    for line in f:
                        parts = line.strip().split("|")
                        if len(parts) >= 6:
                            ts, ip, method, uri, status, ua = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]
                            if uri.startswith("/sub/") and uri.endswith(".json"):
                                uname = uri[5:-5]
                                if uname in user_stats and status in ("200", "304"):
                                    user_stats[uname]["sub_downloads"] += 1
                                    user_stats[uname]["ips"][ip] = user_stats[uname]["ips"].get(ip, 0) + 1
                                    if ua:
                                        user_stats[uname]["uas"][ua] = user_stats[uname]["uas"].get(ua, 0) + 1
                                    user_stats[uname]["last_seen"] = ts
                            elif uri.startswith("/nnect/") and uri.endswith(".html"):
                                uname = uri[7:-5]
                                if uname in user_stats:
                                    user_stats[uname]["page_views"] += 1
                                    user_stats[uname]["ips"][ip] = user_stats[uname]["ips"].get(ip, 0) + 1
                                    user_stats[uname]["last_seen"] = ts
            except Exception:
                continue

        if active_stat:
            _log_cache["mtime"] = active_stat.st_mtime
            _log_cache["size"] = active_stat.st_size
        _log_cache["stats"] = user_stats
        _log_cache["checked_at"] = time.monotonic()
        return user_stats
    except Exception:
        return _log_cache.get("stats", {})

def parse_user_stats(username: str, include_sensitive: bool = False) -> dict:
    all_stats = parse_all_users_stats()
    raw = all_stats.get(username, {
        "sub_downloads": 0,
        "page_views": 0,
        "ips": {},
        "uas": {},
        "last_seen": None
    })

    stored_pin = load_passwords().get(username)
    stored_pin_text = str(stored_pin).strip() if stored_pin is not None else ""
    pin_recoverable = bool(stored_pin_text and not stored_pin_text.startswith("pbkdf2:sha256:"))
    if include_sensitive:
        pin = get_user_pin(username)
        if not stored_pin_text:
            pin_recoverable = True
    else:
        pin = "••••"

    user_uuid = get_user_uuid(username)
    sub_path = f"/sub/{username}_{user_uuid}.json" if user_uuid else ""
    subscription_url = f"https://{DOMAIN}{sub_path}" if include_sensitive and user_uuid else ""
    happ_add_url = f"happ://add/{subscription_url}" if subscription_url else ""

    sorted_ips = sorted(raw["ips"].items(), key=lambda x: x[1], reverse=True)
    top_ips = [{"ip": ip, "count": cnt} for ip, cnt in sorted_ips[:10]]

    sorted_uas = sorted(raw["uas"].items(), key=lambda x: x[1], reverse=True)
    top_uas = [ua for ua, cnt in sorted_uas[:5]]

    unique_ips_count = len(raw["ips"])
    leak_warning = None
    if unique_ips_count > 5:
        leak_warning = f"⚠ Возможная пересылка: подписку скачивали с {unique_ips_count} разных IP"

    xtraffic = get_user_xray_traffic(username)

    return {
        "username": username,
        "pin": pin,
        "pin_recoverable": pin_recoverable,
        "page_views": raw["page_views"],
        "sub_downloads": raw["sub_downloads"],
        "unique_ips_count": unique_ips_count,
        "top_ips": top_ips,
        "last_seen": raw["last_seen"] or "Нет активности",
        "user_agents": top_uas,
        "leak_warning": leak_warning,
        "subscription_url": subscription_url,
        "happ_url": subscription_url,
        "happ_add_url": happ_add_url,
        "landing_url": f"https://{DOMAIN}/nect/{username}",
        "landing_url_with_pin": f"https://{DOMAIN}/nect/{username}?pin={urllib.parse.quote(pin)}" if include_sensitive and pin != "••••" else "",
        "xray": xtraffic,
    }

def add_new_user(username: str, pin: str = None) -> str:
    username = username.strip()
    if not re.match(r"^[A-Za-z0-9_-]{2,32}$", username):
        raise ValueError("Имя пользователя должно содержать 2-32 символов (буквы, цифры, дефис, подчеркивание)")

    users = get_users_list()
    if username in users:
        raise ValueError(f"Пользователь '{username}' уже существует")

    with open(USERS_FILE, "a", encoding="utf-8") as f:
        f.write(f"{username}\n")

    issued_pin = str(pin).strip() if pin else get_user_pin(username)
    if pin:
        set_user_pin(username, issued_pin)

    # Ensure UUID exists in users.json
    try:
        users_file = Path(f"{ETC_DIR}/users.json")
        uuids = {}
        if users_file.exists():
            uuids = json.loads(users_file.read_text(encoding="utf-8"))
        if username not in uuids:
            import uuid
            uuids[username] = str(uuid.uuid4())
            tmp_p = Path(f"/tmp/u_panel_{os.getpid()}.json")
            tmp_p.write_text(json.dumps(uuids, indent=2), encoding="utf-8")
            subprocess.run(["sudo", "cp", str(tmp_p), str(users_file)], check=False)
            subprocess.run(["sudo", "chown", "root:vpndavida", str(users_file)], check=False)
            subprocess.run(["sudo", "chmod", "640", str(users_file)], check=False)
            tmp_p.unlink(missing_ok=True)
    except Exception as e:
        print(f"Error ensuring UUID for {username}: {e}")

    # Run sync via sudo /usr/local/bin/autoXRAY_davida_custom or fallback
    for script_path in ["/usr/local/bin/autoXRAY_davida_custom", "/root/autoXRAY_davida_custom.sh"]:
        if os.path.exists(script_path):
            subprocess.run(["sudo", script_path, "sync", DOMAIN], check=False)
            break
    # Return only to the authenticated create-user request; only the PBKDF2 hash is persisted.
    return issued_pin

def delete_user(username: str) -> bool:
    username = username.strip()
    users = get_users_list()
    if username not in users:
        raise ValueError(f"Пользователь '{username}' не найден")

    new_users = [u for u in users if u != username]
    with open(USERS_FILE, "w", encoding="utf-8") as f:
        for u in new_users:
            f.write(f"{u}\n")

    (WEB_PATH / "sub" / f"{username}.json").unlink(missing_ok=True)
    for p in (WEB_PATH / "sub").glob(f"{username}_*.json"):
        p.unlink(missing_ok=True)
    (WEB_PATH / "nnect" / f"{username}.html").unlink(missing_ok=True)

    pwds = load_passwords()
    if username in pwds:
        del pwds[username]
        save_passwords(pwds)
    return True

def run_sync() -> str:
    script_path = "/root/autoXRAY_davida_custom.sh"
    if os.path.exists(script_path):
        res = subprocess.run(["bash", script_path, "sync", DOMAIN], capture_output=True, text=True)
        return res.stdout
    return "Local sync completed"

# --- HTTP HANDLER ---

class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

class DavidaHandler(BaseHTTPRequestHandler):
    def send_json(self, data: dict, status: int = 200, headers: dict = None):
        content = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Davida-Secret")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS, HEAD")
        if headers:
            for k, v in headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(content)

    def send_error_json(self, message: str, status: int = 400):
        self.send_json({"error": message, "success": False}, status=status)

    def check_auth(self) -> bool:
        auth_header = self.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header[7:].strip()
            if token == get_master_password() or verify_token(token, required_role="admin"):
                return True
        secret_header = self.headers.get("X-Davida-Secret", "")
        if secret_header == get_master_password():
            return True
        cookie_header = self.headers.get("Cookie", "")
        for item in cookie_header.split(";"):
            item = item.strip()
            if item.startswith("davida_auth="):
                token = item[len("davida_auth="):]
                return verify_token(token, required_role="admin")
        return False

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Davida-Secret")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS, HEAD")
        self.end_headers()

    def do_HEAD(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if path in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
        else:
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path in ("/", "/index.html"):
            self.serve_admin_ui()
            return

        if path == "/api/health":
            self.send_json({"status": "ok", "service": "davida-core", "version": "3.0-stealth"})
            return

        if path == "/api/auth/verify":
            self.send_error_json("Method Not Allowed. Use POST /api/auth/user instead", status=405)
            return

        if not self.check_auth():
            self.send_error_json("Unauthorized", status=401)
            return

        if path == "/api/system/memory":
            self.send_json(get_system_memory())
            return

        if path == "/api/stats/overview":
            self.send_json(get_xray_stats_overview())
            return

        if path == "/api/stats/users":
            qs = urllib.parse.parse_qs(parsed.query)
            days = _bounded_history_days(qs.get("days", ["7"])[0], default=7, maximum=365)
            self.send_json(get_users_traffic_period(days))
            return

        if path.startswith("/api/stats/users/"):
            parts = path.strip("/").split("/")
            if len(parts) == 5 and parts[4] == "history":
                username = urllib.parse.unquote(parts[3])
                if username not in get_users_list():
                    self.send_error_json("User not found", status=404)
                    return
                qs = urllib.parse.parse_qs(parsed.query)
                days = _bounded_history_days(qs.get("days", ["30"])[0], default=30, maximum=365)
                self.send_json(get_user_traffic_history(username, days))
                return

        if path == "/api/status":
            nodes = get_node_status()
            users = get_users_list()
            self.send_json({
                "nodes": nodes,
                "total_users": len(users),
                "active_nodes": sum(1 for n in nodes if n.get("online")),
                "domain": DOMAIN,
                "timestamp": int(time.time())
            })
            return

        if path == "/api/nodes/history":
            qs = urllib.parse.parse_qs(parsed.query)
            try:
                hours = int(qs.get("hours", ["24"])[0])
            except (TypeError, ValueError):
                hours = 24
            hours = max(1, min(hours, 2160))
            data = get_pings_history(hours=hours)
            self.send_json(data)
            return

        # Rotate Cluster Master Password
        if path == "/api/admin/rotate_master_secret":
            curr_pass = payload.get("current_password", "").strip()
            new_pass = payload.get("new_password", "").strip()

            if not curr_pass or not new_pass:
                self.send_error_json("Текущий и новый пароль обязательны", status=400)
                return

            curr_hash = hashlib.sha256(curr_pass.encode()).hexdigest()
            if not hmac.compare_digest(curr_hash, get_master_password_hash()):
                self.send_error_json("Неверный текущий мастер-пароль", status=403)
                return

            if len(new_pass) < 10:
                self.send_error_json("Новый пароль должен содержать минимум 10 символов", status=400)
                return

            try:
                res = rotate_cluster_master_password(new_pass)
                new_token = create_token("admin")
                self.send_json({
                    "success": True,
                    "message": f"Мастер-пароль успешно изменен на {len(res['updated_nodes'])} узлах кластера",
                    "token": new_token,
                    "updated_nodes": res["updated_nodes"],
                    "errors": res.get("errors")
                }, headers={"Set-Cookie": f"davida_auth={new_token}; Path=/; HttpOnly; SameSite=Lax; Max-Age={SESSION_DURATION_SEC}"})
            except Exception as e:
                self.send_error_json(f"Ошибка ротации: {e}", status=500)
            return

        if path == "/api/users":
            users = get_users_list()
            stats = [parse_user_stats(u) for u in users]
            self.send_json({"users": stats, "count": len(stats)})
            return

        if path.startswith("/api/users/"):
            username = path[len("/api/users/"):].strip()
            if username in get_users_list():
                self.send_json(parse_user_stats(username, include_sensitive=True))
            else:
                self.send_error_json("User not found", status=404)
            return

        self.send_error_json("Not Found", status=404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        length = int(self.headers.get("Content-Length", 0))
        
        if length > 65536:
            self.send_error_json("Payload too large", status=413)
            return
            
        body = self.rfile.read(length) if length > 0 else b"{}"

        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception:
            payload = {}

        # 1. Admin Login
        if path == "/api/auth/login":
            password = payload.get("password", "")
            pwd_hash = hashlib.sha256(password.encode()).hexdigest()
            if hmac.compare_digest(pwd_hash, get_master_password_hash()):
                token = create_token("admin")
                self.send_json({
                    "success": True,
                    "token": token,
                    "message": "Успешная авторизация"
                }, headers={"Set-Cookie": f"davida_auth={token}; Path=/; HttpOnly; SameSite=Lax; Max-Age={SESSION_DURATION_SEC}"})
            else:
                self.send_error_json("Неверный пароль", status=403)
            return

        # 2. Public User PIN Authorization for Landing Page
        if path == "/api/auth/user":
            username = payload.get("username", "").strip()
            pin = payload.get("pin", "").strip()
            if not username or not pin:
                self.send_error_json("Имя пользователя и PIN обязательны", status=400)
                return

            client_ip = self.headers.get("X-Real-IP") or self.client_address[0]
            if is_pin_rate_limited(client_ip, username):
                self.send_error_json("Слишком много неверных попыток. Подождите 5 минут.", status=429)
                return

            if verify_user_pin(username, pin):
                clear_pin_rate_limit(client_ip, username)
                host = self.headers.get("Host", DOMAIN).split(":")[0]
                if not host or "skam" not in host:
                    host = DOMAIN
                user_uuid = get_user_uuid(username)
                if not user_uuid:
                    self.send_error_json("Защищённая подписка пользователя ещё не создана", status=503)
                    return
                sub_filename = f"{username}_{user_uuid}.json"
                sub_url = f"https://{host}/sub/{sub_filename}"
                happ_url = f"happ://add/{sub_url}"
                self.send_json({
                    "success": True,
                    "message": "Авторизован",
                    "subscription_url": sub_url,
                    "happ_add_url": happ_url,
                    "pin": pin
                })
            else:
                record_failed_pin_attempt(client_ip, username)
                self.send_error_json("Неверный пароль / PIN", status=403)
            return

        # 3. Public User Self-Service Password / PIN Change
        if path == "/api/user/change_pin":
            username = payload.get("username", "").strip()
            current_pin = payload.get("current_pin", "").strip()
            new_pin = payload.get("new_pin", "").strip()
            if not username or not current_pin or not new_pin:
                self.send_error_json("Все поля обязательны", status=400)
                return
            if not verify_user_pin(username, current_pin):
                self.send_error_json("Неверный текущий пароль", status=403)
                return
            if len(new_pin) < 4:
                self.send_error_json("Пароль должен быть от 4 символов", status=400)
                return
            try:
                set_user_pin(username, new_pin)
                self.send_json({"success": True, "message": "Пароль успешно изменен"})
            except Exception as e:
                self.send_error_json(str(e), status=500)
            return

        # Admin Auth Required for Remaining Endpoints
        if not self.check_auth():
            self.send_error_json("Unauthorized", status=401)
            return

        # Rotate Cluster Master Password
        if path == "/api/admin/rotate_master_secret":
            curr_pass = payload.get("current_password", "").strip()
            new_pass = payload.get("new_password", "").strip()

            if not curr_pass or not new_pass:
                self.send_error_json("Текущий и новый пароль обязательны", status=400)
                return

            curr_hash = hashlib.sha256(curr_pass.encode()).hexdigest()
            if not hmac.compare_digest(curr_hash, get_master_password_hash()):
                self.send_error_json("Неверный текущий мастер-пароль", status=403)
                return

            if len(new_pass) < 10:
                self.send_error_json("Новый пароль должен содержать минимум 10 символов", status=400)
                return

            try:
                res = rotate_cluster_master_password(new_pass)
                new_token = create_token("admin")
                self.send_json({
                    "success": True,
                    "message": f"Мастер-пароль успешно изменен на {len(res['updated_nodes'])} узлах кластера",
                    "token": new_token,
                    "updated_nodes": res["updated_nodes"],
                    "errors": res.get("errors")
                }, headers={"Set-Cookie": f"davida_auth={new_token}; Path=/; HttpOnly; SameSite=Lax; Max-Age={SESSION_DURATION_SEC}"})
            except Exception as e:
                self.send_error_json(f"Ошибка ротации: {e}", status=500)
            return

        if path == "/api/users":
            username = payload.get("username", "")
            pin = payload.get("pin", None)
            try:
                initial_pin = add_new_user(username, pin=pin)
                stats = parse_user_stats(username)
                self.send_json({"success": True, "user": stats, "initial_pin": initial_pin, "message": f"Пользователь {username} создан"}, headers={"Cache-Control": "no-store"})
            except ValueError as e:
                self.send_error_json(str(e), status=400)
            return

        if path == "/api/users/pin":
            username = payload.get("username", "").strip()
            pin = payload.get("pin", "").strip()
            try:
                set_user_pin(username, pin)
                self.send_json({"success": True, "pin": pin, "message": f"PIN для {username} обновлен"}, headers={"Cache-Control": "no-store"})
            except Exception as e:
                self.send_error_json(str(e), status=400)
            return

        if path == "/api/sync":
            log = run_sync()
            self.send_json({"success": True, "log": log, "message": "Синхронизация завершена"})
            return

        if path == "/api/system/memory/log":
            desc = payload.get("description") or payload.get("message") or ""
            if not desc:
                self.send_error_json("Описание обязательно", status=400)
                return
            author = payload.get("author", "agent")
            category = payload.get("category", "OPERATIONS")
            files = payload.get("files", "N/A")
            rollback = payload.get("rollback", "N/A")
            log_system_memory(desc, author=author, category=category, files=files, rollback=rollback)
            self.send_json({"success": True, "message": "Запись добавлена в CHANGELOG.md"})
            return

        self.send_error_json("Not Found", status=404)

    def do_DELETE(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if not self.check_auth():
            self.send_error_json("Unauthorized", status=401)
            return

        if path.startswith("/api/users/"):
            username = path[len("/api/users/"):].strip()
            try:
                delete_user(username)
                self.send_json({"success": True, "message": f"Пользователь {username} удален"})
            except ValueError as e:
                self.send_error_json(str(e), status=400)
            return

        self.send_error_json("Not Found", status=404)

    def serve_admin_ui(self):
        ui_path = Path(__file__).parent / "static" / "index.html"
        if ui_path.exists():
            content = ui_path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_error_json("Admin UI file not found", status=404)

def run():
    init_db()

    collector_thread = threading.Thread(target=metrics_collector_loop, daemon=True)
    collector_thread.start()
    print("[*] Stealth Node Metrics Collector started (15s parallel, SQLite)")

    xray_collector_thread = threading.Thread(target=xray_stats_collector_loop, daemon=True)
    xray_collector_thread.start()
    print("[*] Xray stats collector started (10s interval, SQLite Zero Loss)")

    server_address = (HOST, PORT)
    httpd = ThreadingHTTPServer(server_address, DavidaHandler)
    print(f"[*] Davida Core API v3.0 running on http://{HOST}:{PORT}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down Davida Core API")
        httpd.server_close()

if __name__ == "__main__":
    run()
