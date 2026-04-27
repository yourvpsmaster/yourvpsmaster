#!/bin/bash
# ============================================================
#   YOURVPSMASTER - INSTALADOR PRINCIPAL
#   Soporte: Ubuntu 22.04 LTS x86_64
#   Autor: YourVPSMaster
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_VERSION="1.0.0"
INSTALL_DIR="/opt/yourvpsmaster"
GITHUB_RAW="https://raw.githubusercontent.com/yourvpsmaster/yourvpsmaster/main"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Este script debe ejecutarse como root"
        exit 1
    fi
}

check_os() {
    if ! grep -qi "ubuntu 22" /etc/os-release 2>/dev/null; then
        echo -e "${YELLOW}[AVISO]${NC} Recomendado Ubuntu 22.04. Continuando de todas formas..."
    fi
}

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ██╗   ██╗ ██████╗ ██╗   ██╗██████╗ ██╗   ██╗██████╗ ███████╗"
    echo "  ╚██╗ ██╔╝██╔═══██╗██║   ██║██╔══██╗██║   ██║██╔══██╗██╔════╝"
    echo "   ╚████╔╝ ██║   ██║██║   ██║██████╔╝██║   ██║██████╔╝███████╗"
    echo "    ╚██╔╝  ██║   ██║██║   ██║██╔══██╗╚██╗ ██╔╝██╔═══╝ ╚════██║"
    echo "     ██║   ╚██████╔╝╚██████╔╝██║  ██║ ╚████╔╝ ██║     ███████║"
    echo "     ╚═╝    ╚═════╝  ╚═════╝ ╚═╝  ╚═╝  ╚═══╝  ╚═╝     ╚══════╝"
    echo -e "${YELLOW}                    ██╗   ██╗██████╗ ███████╗"
    echo "                    ██║   ██║██╔══██╗██╔════╝"
    echo "                    ██║   ██║██████╔╝███████╗"
    echo "                    ╚██╗ ██╔╝██╔═══╝ ╚════██║"
    echo "                     ╚████╔╝ ██║     ███████║"
    echo -e "                      ╚═══╝  ╚═╝     ╚══════╝${NC}"
    echo ""
    echo -e "${MAGENTA}  ════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   🍄  YourVPSMaster v${SCRIPT_VERSION} - Ubuntu 22.04 LTS  🍄${NC}"
    echo -e "${MAGENTA}  ════════════════════════════════════════════════════${NC}"
    echo ""
}

install_dependencies() {
    echo -e "${CYAN}[*]${NC} Actualizando sistema e instalando dependencias..."
    apt-get update -qq
    apt-get install -y -qq \
        curl wget git unzip zip \
        python3 python3-pip python3-venv \
        net-tools iptables \
        screen tmux \
        openssl ca-certificates \
        nginx \
        dnsutils bind9-utils \
        jq \
        lsof \
        cron \
        build-essential \
        software-properties-common \
        apt-transport-https \
        gnupg2 2>/dev/null

    pip3 install -q websockets requests aiohttp 2>/dev/null
    echo -e "${GREEN}[✓]${NC} Dependencias instaladas"
}

install_main_script() {
    echo -e "${CYAN}[*]${NC} Instalando YourVPSMaster..."
    mkdir -p "$INSTALL_DIR"/{logs,configs,ssl,pids,protocols,tools,core,public}

    # Descargar archivos desde GitHub
    local BASE="${GITHUB_RAW}"
    local FILES=(
        "core/lib.sh" "core/menu.sh" "core/protocols_menu.sh"
        "core/autostart.sh" "core/autostart_toggle.sh" "core/init_placeholders.sh"
        "protocols/slowdns.sh" "protocols/proxy_python.sh" "protocols/openssh.sh"
        "tools/user_control.sh" "tools/badvpn.sh" "tools/bbr.sh"
        "tools/firewall.sh" "tools/vps_info.sh" "tools/restart_services.sh"
        "tools/update_remove.sh" "tools/setup_nginx.sh"
    )

    for f in "${FILES[@]}"; do
        local DIR
        DIR=$(dirname "${INSTALL_DIR}/${f}")
        mkdir -p "$DIR"
        wget -q "${BASE}/${f}" -O "${INSTALL_DIR}/${f}" 2>/dev/null || true
        chmod +x "${INSTALL_DIR}/${f}" 2>/dev/null || true
    done

    # Inicializar config por defecto
    mkdir -p "$CONFIG_DIR"
    [[ ! -f "${CONFIG_DIR}/main.conf" ]] && touch "${CONFIG_DIR}/main.conf"
    [[ ! -f "${CONFIG_DIR}/ws_proxy.json" ]] && cat > "${CONFIG_DIR}/ws_proxy.json" << 'JSONEOF'
{
    "ports": [80, 8080, 3128, 2082],
    "ssh_host": "127.0.0.1",
    "ssh_port": 22,
    "response_101": true,
    "custom_response": "",
    "buffer_size": 65536
}
JSONEOF

    # Crear placeholders para módulos pendientes
    bash "${INSTALL_DIR}/core/init_placeholders.sh" 2>/dev/null || true

    # Configurar nginx
    bash "${INSTALL_DIR}/tools/setup_nginx.sh" 2>/dev/null || true

    # Crear comando global
    cat > /usr/local/bin/yourvpsmaster << 'EOFCMD'
#!/bin/bash
bash /opt/yourvpsmaster/core/menu.sh "$@"
EOFCMD
    chmod +x /usr/local/bin/yourvpsmaster

    # Auto-inicio
    cat > /etc/systemd/system/yourvpsmaster.service << 'EOFSVC'
[Unit]
Description=YourVPSMaster Auto-Start Service
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/yourvpsmaster/core/autostart.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFSVC

    systemctl daemon-reload
    systemctl enable yourvpsmaster 2>/dev/null
    echo -e "${GREEN}[✓]${NC} YourVPSMaster instalado en ${INSTALL_DIR}"
}

main() {
    check_root
    check_os
    show_banner
    echo -e "${YELLOW}[*]${NC} Iniciando instalación de YourVPSMaster..."
    sleep 1
    install_dependencies
    install_main_script
    echo ""
    echo -e "${GREEN}  ✅ ¡Instalación completada exitosamente!${NC}"
    echo -e "${CYAN}  👉 Ejecuta: ${YELLOW}yourvpsmaster${NC} para iniciar"
    echo ""
}

main
