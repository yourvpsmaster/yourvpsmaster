#!/bin/bash
# ============================================================
#   YOURVPSMASTER - OPENSSH MANAGER
# ============================================================
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

ssh_menu() {
    while true; do
        clear
        show_header
        local SSH_PORT
        SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
        echo ""
        echo -e "${BMAGENTA}  🍄  OpenSSH MANAGER  🍄${NC}"
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo -e "  ${GREEN}• Estado : ${NC}$(service_status ssh)"
        echo -e "  ${GREEN}• Puerto : ${CYAN}${SSH_PORT}${NC}"
        echo ""
        echo -e "${BYELLOW}  [1]${NC} ➪ Iniciar SSH"
        echo -e "${BYELLOW}  [2]${NC} ➪ Detener SSH"
        echo -e "${BYELLOW}  [3]${NC} ➪ Cambiar puerto SSH"
        echo -e "${BYELLOW}  [4]${NC} ➪ Configurar SSH (Banner, MaxSessions, etc)"
        echo -e "${BYELLOW}  [5]${NC} ➪ Ver usuarios conectados"
        echo ""
        echo -e "  ${BYELLOW}[0]${NC} ➪ ${BRED}[ REGRESAR ]${NC}"
        echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt
        case "$opt" in
            1) systemctl start ssh; echo -e "${GREEN}  [✓] SSH iniciado${NC}"; press_enter ;;
            2) systemctl stop ssh; echo -e "${RED}  [✓] SSH detenido${NC}"; press_enter ;;
            3) change_ssh_port ;;
            4) configure_ssh ;;
            5) who; w; press_enter ;;
            0) return ;;
        esac
    done
}

change_ssh_port() {
    echo -ne "${MAGENTA}  ► Nuevo puerto SSH: ${NC}"
    read -r NPORT
    [[ ! "$NPORT" =~ ^[0-9]+$ ]] && { echo -e "${RED}  Inválido${NC}"; sleep 2; return; }
    sed -i "s/^Port .*/Port ${NPORT}/" /etc/ssh/sshd_config
    grep -q "^Port" /etc/ssh/sshd_config || echo "Port ${NPORT}" >> /etc/ssh/sshd_config
    systemctl restart ssh
    iptables -I INPUT -p tcp --dport "$NPORT" -j ACCEPT 2>/dev/null
    config_set "SSH_PORT" "$NPORT"
    echo -e "${GREEN}  [✓] Puerto SSH cambiado a ${NPORT}${NC}"
    press_enter
}

configure_ssh() {
    cat > /etc/ssh/sshd_config.d/yourvpsmaster.conf << 'SSHEOF'
MaxSessions 1024
MaxAuthTries 6
PermitRootLogin yes
PasswordAuthentication yes
Banner /etc/ssh/banner
ClientAliveInterval 60
ClientAliveCountMax 3
X11Forwarding yes
AllowTcpForwarding yes
GatewayPorts yes
SSHEOF

    # Banner
    cat > /etc/ssh/banner << 'BNREOF'
╔══════════════════════════════════════╗
║     YourVPSMaster - Bienvenido       ║
╚══════════════════════════════════════╝
BNREOF

    systemctl restart ssh
    echo -e "${GREEN}  [✓] SSH configurado con MaxSessions=1024${NC}"
    press_enter
}

ssh_menu
