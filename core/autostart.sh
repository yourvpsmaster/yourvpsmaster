#!/bin/bash
# ============================================================
#   YOURVPSMASTER - AUTOSTART
# ============================================================
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh" 2>/dev/null

LOG="${INSTALL_DIR}/logs/autostart.log"
mkdir -p "${INSTALL_DIR}/logs" "${INSTALL_DIR}/pids"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

log "=== YourVPSMaster AutoStart ==="

# WebSocket Proxy
if [[ "$(config_get PROTO_WS)" == "1" ]]; then
    if ! pgrep -f "ws_proxy.py" >/dev/null 2>&1; then
        nohup python3 "${INSTALL_DIR}/protocols/ws_python/ws_proxy.py" \
            >> "$LOG" 2>&1 &
        log "WebSocket Proxy iniciado (PID: $!)"
    fi
fi

# SlowDNS
if [[ "$(config_get PROTO_SLOWDNS)" == "1" ]]; then
    if ! pgrep -f "slowdns_server.py" >/dev/null 2>&1; then
        nohup python3 "${INSTALL_DIR}/protocols/slowdns/slowdns_server.py" \
            >> "$LOG" 2>&1 &
        log "SlowDNS iniciado (PID: $!)"
    fi
fi

# BadVPN
if [[ "$(config_get PROTO_BADVPN)" == "1" ]]; then
    local PORTS="7200 7300"
    local SAVED
    SAVED=$(config_get "BADVPN_PORTS")
    [[ -n "$SAVED" ]] && PORTS=$(echo "$SAVED" | tr ',' ' ')
    for p in $PORTS; do
        if [[ -f "${INSTALL_DIR}/tools/badvpn/badvpn-udpgw" ]]; then
            nohup "${INSTALL_DIR}/tools/badvpn/badvpn-udpgw" \
                --listen-addr "0.0.0.0:${p}" --max-clients 500 \
                >> "$LOG" 2>&1 &
        elif [[ -f "${INSTALL_DIR}/tools/badvpn/udpgw.py" ]]; then
            nohup python3 "${INSTALL_DIR}/tools/badvpn/udpgw.py" "$p" \
                >> "$LOG" 2>&1 &
        fi
        log "BadVPN iniciado en puerto ${p}"
    done
fi

log "AutoStart completado"
