#!/bin/bash
# ============================================================
#   YOURVPSMASTER - FIREWALL IPTABLES
# ============================================================
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

firewall_menu() {
    while true; do
        clear
        show_header
        echo ""
        echo -e "${BMAGENTA}  🍄  FIREWALL (IPTABLES)  🍄${NC}"
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${BYELLOW}  [1]${NC} ➪ Ver reglas actuales"
        echo -e "${BYELLOW}  [2]${NC} ➪ Abrir puerto"
        echo -e "${BYELLOW}  [3]${NC} ➪ Cerrar puerto"
        echo -e "${BYELLOW}  [4]${NC} ➪ Bloquear IP"
        echo -e "${BYELLOW}  [5]${NC} ➪ Desbloquear IP"
        echo -e "${BYELLOW}  [6]${NC} ➪ Abrir puertos YourVPSMaster (todos)"
        echo -e "${BYELLOW}  [7]${NC} ➪ Guardar reglas (persistente)"
        echo -e "${BYELLOW}  [8]${NC} ➪ Limpiar todas las reglas"
        echo ""
        echo -e "  ${BYELLOW}[0]${NC} ➪ ${BRED}[ REGRESAR ]${NC}"
        echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt
        case "$opt" in
            1) iptables -L -n --line-numbers 2>/dev/null | head -60; press_enter ;;
            2) open_port ;;
            3) close_port ;;
            4) block_ip ;;
            5) unblock_ip ;;
            6) open_all_ports ;;
            7) save_rules ;;
            8) flush_rules ;;
            0) return ;;
        esac
    done
}

open_port() {
    echo -ne "${MAGENTA}  ► Puerto a abrir: ${NC}"
    read -r PORT
    echo -ne "${MAGENTA}  ► Protocolo [tcp/udp/both]: ${NC}"
    read -r PROTO
    case "$PROTO" in
        udp) iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null ;;
        both)
            iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null
            iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null ;;
        *) iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null ;;
    esac
    echo -e "${GREEN}  [✓] Puerto ${PORT} abierto${NC}"
    press_enter
}

close_port() {
    echo -ne "${MAGENTA}  ► Puerto a cerrar: ${NC}"
    read -r PORT
    iptables -D INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null
    echo -e "${RED}  [✓] Puerto ${PORT} cerrado${NC}"
    press_enter
}

block_ip() {
    echo -ne "${MAGENTA}  ► IP a bloquear: ${NC}"
    read -r IP
    iptables -I INPUT -s "$IP" -j DROP 2>/dev/null
    echo -e "${RED}  [✓] IP ${IP} bloqueada${NC}"
    press_enter
}

unblock_ip() {
    echo -ne "${MAGENTA}  ► IP a desbloquear: ${NC}"
    read -r IP
    iptables -D INPUT -s "$IP" -j DROP 2>/dev/null
    echo -e "${GREEN}  [✓] IP ${IP} desbloqueada${NC}"
    press_enter
}

open_all_ports() {
    echo -e "${CYAN}  [*] Abriendo todos los puertos de YourVPSMaster...${NC}"
    local PORTS=(22 80 443 8080 3128 2082 5300 7200 7300 9090 2095 2096 11111 62789 65000 81)
    for p in "${PORTS[@]}"; do
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null
    done
    echo -e "${GREEN}  [✓] Todos los puertos abiertos${NC}"
    press_enter
}

save_rules() {
    apt-get install -y -qq iptables-persistent 2>/dev/null
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
    echo -e "${GREEN}  [✓] Reglas guardadas permanentemente${NC}"
    press_enter
}

flush_rules() {
    confirm "¿Limpiar TODAS las reglas de iptables?" || return
    iptables -F
    iptables -X
    iptables -Z
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    echo -e "${GREEN}  [✓] Reglas limpiadas${NC}"
    press_enter
}

firewall_menu
