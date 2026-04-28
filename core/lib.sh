#!/bin/bash
# ============================================================
#   YOURVPSMASTER - LIBRERÍA DE COLORES Y UI
#   Paleta: fondo oscuro / neon como en las capturas
# ============================================================

# ── Colores base ─────────────────────────────────────────────
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

# ── Colores brillantes (bold) ─────────────────────────────────
BGREEN='\033[1;32m'
BRED='\033[1;31m'
BYELLOW='\033[1;33m'
BCYAN='\033[1;36m'
BMAGENTA='\033[1;35m'
BWHITE='\033[1;37m'

# ── Alias semánticos para consistencia con capturas ──────────
#  Números de opción [1],[2]...  → CYAN
#  Labels/nombres               → BYELLOW o CYAN
#  Valores (puertos, IPs)       → YELLOW
#  Labels de campo              → GREEN
#  Secciones / títulos          → BMAGENTA
#  [ON]                         → GREEN
#  [OFF]                        → RED
#  Separadores                  → YELLOW
#  Prompt ->  /  ►              → MAGENTA
#  Texto informativo            → WHITE
#  (#BETA) / [REF]              → CYAN

# ── Rutas ─────────────────────────────────────────────────────
INSTALL_DIR="/opt/yourvpsmaster"
CONFIG_DIR="${INSTALL_DIR}/configs"
LOG_DIR="${INSTALL_DIR}/logs"
PID_DIR="${INSTALL_DIR}/pids"
SSL_DIR="${INSTALL_DIR}/ssl"

# ─────────────────────────────────────────────────────────────
#   UTILIDADES DE SISTEMA
# ─────────────────────────────────────────────────────────────
get_ip() {
    curl -s4 --max-time 3 ifconfig.me 2>/dev/null || \
    curl -s4 --max-time 3 icanhazip.com 2>/dev/null || \
    hostname -I | awk '{print $1}'
}

get_date() {
    date '+%d/%m/%Y-%H:%M'
}

get_os() {
    grep -oP '(?<=PRETTY_NAME=")[^"]+' /etc/os-release 2>/dev/null | head -1 || \
    lsb_release -d 2>/dev/null | awk -F: '{print $2}' | xargs || \
    echo "Ubuntu 22.04"
}

get_cpu_count() { nproc; }

get_ram_total() { free -h | awk '/^Mem:/{print $2}'; }
get_ram_free()  { free -h | awk '/^Mem:/{print $4}'; }
get_ram_used()  { free -h | awk '/^Mem:/{print $3}'; }
get_buffer()    { free -h | awk '/^Mem:/{print $6}'; }

get_ram_pct() {
    free | awk '/^Mem:/{printf("%.2f%%", $3/$2*100)}'
}

get_cpu_pct() {
    top -bn1 2>/dev/null | grep -i "cpu(s)" | awk '{print $2+$4"%"}' || echo "N/A"
}

# ─────────────────────────────────────────────────────────────
#   ESTADO DE SERVICIOS Y PUERTOS
# ─────────────────────────────────────────────────────────────
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
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
       lsof -i ":${port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

is_installed() {
    dpkg -l "$1" &>/dev/null && echo 1 || echo 0
}

# ─────────────────────────────────────────────────────────────
#   CONFIG KEY/VALUE
# ─────────────────────────────────────────────────────────────
config_get() {
    local key="$1"
    local file="${CONFIG_DIR}/main.conf"
    [[ -f "$file" ]] && grep "^${key}=" "$file" | cut -d= -f2- | head -1 || echo ""
}

config_set() {
    local key="$1"
    local val="$2"
    local file="${CONFIG_DIR}/main.conf"
    mkdir -p "$CONFIG_DIR"
    touch "$file"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

# ─────────────────────────────────────────────────────────────
#   UI HELPERS
# ─────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────
#   CABECERA PRINCIPAL
#   Replica exactamente la captura de pantalla:
#     S.O / Base / CPU's en verde+blanco
#     IP / FECHA en verde+amarillo
#     RAM stats en verde+amarillo
# ─────────────────────────────────────────────────────────────
show_header() {
    local IP DT OS CPU RAM_TOTAL RAM_FREE RAM_USED RAM_PCT CPU_PCT BUF
    IP=$(get_ip)
    DT=$(get_date)
    OS=$(get_os)
    CPU=$(get_cpu_count)
    RAM_TOTAL=$(get_ram_total)
    RAM_FREE=$(get_ram_free)
    RAM_USED=$(get_ram_used)
    RAM_PCT=$(get_ram_pct)
    CPU_PCT=$(get_cpu_pct)
    BUF=$(get_buffer)

    echo -e "${CYAN}  ═══════════════════════════════════════════════════════${NC}"
    echo -e "${BMAGENTA}  🍄  YourVPSMaster v1.0.0 - Ubuntu 22.04 LTS  🍄${NC}"
    echo -e "${CYAN}  ═══════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}• S.O: ${WHITE}${OS}${NC}  ${GREEN}• Base:${WHITE}x86_64${NC}  ${GREEN}• CPU's:${YELLOW}${CPU}${NC}"
    echo -e "  ${GREEN}• IP: ${WHITE}${IP}${NC}  ${GREEN}• FECHA: ${YELLOW}${DT}${NC}"
    echo -e "${CYAN}  ───────────────────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}• TOTAL: ${YELLOW}${RAM_TOTAL}${NC}  ${GREEN}• M|LIBRE: ${YELLOW}${RAM_FREE}${NC}  ${GREEN}• EN USO: ${YELLOW}${RAM_USED}${NC}"
    echo -e "  ${GREEN}• U/RAM: ${YELLOW}${RAM_PCT}${NC}  ${GREEN}• U/CPU: ${YELLOW}${CPU_PCT}${NC}  ${GREEN}• BUFFER: ${YELLOW}${BUF}${NC}"
    echo -e "${CYAN}  ═══════════════════════════════════════════════════════${NC}"
}

# ─────────────────────────────────────────────────────────────
#   TABLA DE PUERTOS (segunda captura)
#   SSH / WS-Epro / SOCKS  en verde+amarillo
# ─────────────────────────────────────────────────────────────
show_ports() {
    local SSH_P SLOW WS_P NGINX_P SOCKS_P
    SSH_P=$(config_get "SSH_PORT");  SSH_P="${SSH_P:-22}"
    SLOW=$(config_get "SLOWDNS_PORT"); SLOW="${SLOW:-5300}"
    WS_P=$(config_get "WS_PORT");    WS_P="${WS_P:-80}"
    NGINX_P=$(config_get "NGINX_PORT"); NGINX_P="${NGINX_P:-81}"
    SOCKS_P=$(config_get "SOCKS_PORT"); SOCKS_P="${SOCKS_P:-2082}"

    echo -e "  ${GREEN}• SSH: ${YELLOW}${SSH_P}${NC}           ${GREEN}• System-DNS: ${YELLOW}53${NC}"
    echo -e "  ${GREEN}• WS-Epro: ${YELLOW}${WS_P}${NC}        ${GREEN}• WEB-NGinx: ${YELLOW}${NGINX_P}${NC}"
    echo -e "  ${GREEN}• SOCKS/PYTHON3: ${YELLOW}${SOCKS_P}${NC}   ${GREEN}• XRAY/UI: ${YELLOW}2095${NC}"
    echo -e "  ${GREEN}• BadVPN: ${YELLOW}7200${NC}/${YELLOW}7300${NC}   ${GREEN}• XUI/WEB: ${YELLOW}9090${NC}"
    echo -e "  ${GREEN}• SlowDNS: ${YELLOW}${SLOW}${NC}        ${GREEN}• Hysteria2: ${YELLOW}65000${NC}"
    echo -e "${CYAN}  ─────────────────────────────────────────────────────${NC}"
}
