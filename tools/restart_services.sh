#!/bin/bash
# YOURVPSMASTER - REINICIAR SERVICIOS
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

clear
show_header
echo ""
echo -e "${BMAGENTA}  🍄  REINICIAR SERVICIOS  🍄${NC}"
echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
echo ""

restart_service() {
    local name="$1"
    local svc="$2"
    echo -ne "  Reiniciando ${name}... "
    if systemctl restart "$svc" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${YELLOW}[SKIP]${NC}"
    fi
}

restart_service "SSH"           "ssh"
restart_service "Nginx"         "nginx"
restart_service "SlowDNS"       "slowdns-yourvpsmaster"
restart_service "WS Proxy"      "ws-proxy-yourvpsmaster"
restart_service "BadVPN"        "badvpn-yourvpsmaster"

# Reiniciar procesos Python
echo -ne "  Reiniciando procesos Python... "
pkill -f "ws_proxy.py" 2>/dev/null
pkill -f "slowdns_server.py" 2>/dev/null
sleep 1
nohup python3 "${INSTALL_DIR}/protocols/ws_python/ws_proxy.py" \
    > "${LOG_DIR}/ws_proxy.log" 2>&1 &
nohup python3 "${INSTALL_DIR}/protocols/slowdns/slowdns_server.py" \
    > "${LOG_DIR}/slowdns.log" 2>&1 &
echo -e "${GREEN}[OK]${NC}"

echo ""
echo -e "${GREEN}  [✓] Servicios reiniciados${NC}"
press_enter
