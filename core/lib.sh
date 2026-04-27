#!/bin/bash
# ============================================================
#   YOURVPSMASTER - LIBRERÍA DE COLORES Y UI
# ============================================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
BGREEN='\033[1;32m'
BRED='\033[1;31m'
BYELLOW='\033[1;33m'
BCYAN='\033[1;36m'
BMAGENTA='\033[1;35m'

INSTALL_DIR="/opt/yourvpsmaster"
CONFIG_DIR="${INSTALL_DIR}/configs"
LOG_DIR="${INSTALL_DIR}/logs"
PID_DIR="${INSTALL_DIR}/pids"
SSL_DIR="${INSTALL_DIR}/ssl"

get_ip() {
    curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

get_date() {
    date '+%d/%m/%Y-%H:%M'
}

get_os() {
    lsb_release -d 2>/dev/null | awk -F: '{print $2}' | xargs || echo "Ubuntu 22.04"
}

get_cpu_count() {
    nproc
}

get_ram_total() {
    free -h | awk '/Mem:/{print $2}'
}

get_ram_free() {
    free -h | awk '/Mem:/{print $4}'
}

get_ram_used() {
    free -h | awk '/Mem:/{print $3}'
}

get_ram_pct() {
    free | awk '/Mem:/{printf("%.2f%%", $3/$2*100)}'
}

get_cpu_pct() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2+$4"%"}'
}

get_buffer() {
    free -h | awk '/Mem:/{print $6}'
}

service_status() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

port_status() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || lsof -i ":${port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

is_installed() {
    local pkg="$1"
    dpkg -l "$pkg" &>/dev/null && echo 1 || echo 0
}

config_get() {
    local key="$1"
    local file="${CONFIG_DIR}/main.conf"
    [[ -f "$file" ]] && grep "^${key}=" "$file" | cut -d= -f2- || echo ""
}

config_set() {
    local key="$1"
    local val="$2"
    local file="${CONFIG_DIR}/main.conf"
    mkdir -p "$CONFIG_DIR"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

press_enter() {
    echo ""
    echo -e "${DIM}  Presiona [Enter] para continuar...${NC}"
    read -r
}

confirm() {
    local msg="${1:-¿Continuar?}"
    echo -ne "${YELLOW}  [?] ${msg} [s/N]: ${NC}"
    read -r resp
    [[ "$resp" =~ ^[sS]$ ]]
}

show_header() {
    local IP
    IP=$(get_ip)
    local DT
    DT=$(get_date)
    local OS
    OS=$(get_os)
    local CPU
    CPU=$(get_cpu_count)
    local RAM_TOTAL
    RAM_TOTAL=$(get_ram_total)
    local RAM_FREE
    RAM_FREE=$(get_ram_free)
    local RAM_USED
    RAM_USED=$(get_ram_used)
    local RAM_PCT
    RAM_PCT=$(get_ram_pct)
    local CPU_PCT
    CPU_PCT=$(get_cpu_pct)
    local BUF
    BUF=$(get_buffer)

    echo -e "${CYAN}  ═══════════════════════════════════════════════════════${NC}"
    echo -e "${BCYAN}  🍄  YourVPSMaster v1.0.0 - Ubuntu 22.04 LTS  🍄${NC}"
    echo -e "${CYAN}  ═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  • S.O: ${WHITE}${OS}${NC}  ${GREEN}• Base:${WHITE}x86_64${NC}  ${GREEN}• CPU's:${YELLOW}${CPU}${NC}"
    echo -e "${GREEN}  • IP: ${WHITE}${IP}${NC}  ${GREEN}• FECHA: ${YELLOW}${DT}${NC}"
    echo -e "${CYAN}  ───────────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}  • TOTAL: ${YELLOW}${RAM_TOTAL}${NC}  ${GREEN}• M|LIBRE: ${YELLOW}${RAM_FREE}${NC}  ${GREEN}• EN USO: ${YELLOW}${RAM_USED}${NC}"
    echo -e "${GREEN}  • U/RAM: ${YELLOW}${RAM_PCT}${NC}  ${GREEN}• U/CPU: ${YELLOW}${CPU_PCT}${NC}  ${GREEN}• BUFFER: ${YELLOW}${BUF}${NC}"
    echo -e "${CYAN}  ═══════════════════════════════════════════════════════${NC}"
}

show_ports() {
    local SSH_P SLOW WS_P NGINX_P SOCKS_P
    SSH_P=$(config_get "SSH_PORT" || echo "22")
    SLOW=$(config_get "SLOWDNS_PORT" || echo "5300")
    WS_P=$(config_get "WS_PORT" || echo "80")
    NGINX_P=$(config_get "NGINX_PORT" || echo "81")
    SOCKS_P=$(config_get "SOCKS_PORT" || echo "2082")

    echo -e "  ${GREEN}• SSH: ${YELLOW}${SSH_P}${NC}          ${GREEN}• System-DNS: ${YELLOW}53${NC}"
    echo -e "  ${GREEN}• WS-Epro: ${YELLOW}${WS_P}${NC}       ${GREEN}• WEB-NGinx: ${YELLOW}${NGINX_P}${NC}"
    echo -e "  ${GREEN}• SOCKS/PYTHON3: ${YELLOW}${SOCKS_P}${NC}  ${GREEN}• XRAY/UI: ${YELLOW}2095${NC}"
    echo -e "  ${GREEN}• BadVPN: ${YELLOW}7200${NC}/${YELLOW}7300${NC}  ${GREEN}• XUI/WEB: ${YELLOW}9090${NC}"
    echo -e "  ${GREEN}• SlowDNS: ${YELLOW}${SLOW}${NC}       ${GREEN}• Hysteria2: ${YELLOW}65000${NC}"
    echo -e "${CYAN}  ─────────────────────────────────────────────────────${NC}"
}
