#!/bin/bash
# ============================================================
#   YOURVPSMASTER - BBR TCP OPTIMIZER
# ============================================================
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

bbr_menu() {
    while true; do
        clear
        show_header
        local CURRENT_CC
        CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        local CURRENT_QDISC
        CURRENT_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        echo ""
        echo -e "${BMAGENTA}  🍄  TCP BBR OPTIMIZER  🍄${NC}"
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo -e "  ${GREEN}• Algoritmo actual : ${CYAN}${CURRENT_CC}${NC}"
        echo -e "  ${GREEN}• Queue Disc       : ${CYAN}${CURRENT_QDISC}${NC}"
        echo ""
        echo -e "${BYELLOW}  [1]${NC} ➪ Activar BBR (recomendado)"
        echo -e "${BYELLOW}  [2]${NC} ➪ Activar BBR + fq_codel"
        echo -e "${BYELLOW}  [3]${NC} ➪ Activar BBR + cake (máximo rendimiento)"
        echo -e "${BYELLOW}  [4]${NC} ➪ Optimización avanzada de red"
        echo -e "${BYELLOW}  [5]${NC} ➪ Restaurar valores por defecto"
        echo -e "${BYELLOW}  [6]${NC} ➪ Ver estadísticas de red"
        echo ""
        echo -e "  ${BYELLOW}[0]${NC} ➪ ${BRED}[ REGRESAR ]${NC}"
        echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt
        case "$opt" in
            1) enable_bbr "fq" ;;
            2) enable_bbr "fq_codel" ;;
            3) enable_bbr "cake" ;;
            4) advanced_optimization ;;
            5) restore_defaults ;;
            6) show_network_stats ;;
            0) return ;;
        esac
    done
}

enable_bbr() {
    local QDISC="${1:-fq}"
    echo -e "${CYAN}  [*] Activando BBR con ${QDISC}...${NC}"

    # Verificar soporte BBR
    if ! modprobe tcp_bbr 2>/dev/null; then
        echo -e "${YELLOW}  [!] Módulo BBR no disponible en este kernel${NC}"
        echo -e "${CYAN}  [*] Intentando con cubic optimizado...${NC}"
        ALGO="cubic"
    else
        ALGO="bbr"
    fi

    cat > /etc/sysctl.d/99-yourvpsmaster-bbr.conf << SYSEOF
# YourVPSMaster - BBR + Red Optimizada
net.core.default_qdisc=${QDISC}
net.ipv4.tcp_congestion_control=${ALGO}
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=16384
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 16384 134217728
net.ipv4.tcp_mtu_probing=1
net.core.netdev_max_backlog=250000
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=1024 65535
SYSEOF

    sysctl -p /etc/sysctl.d/99-yourvpsmaster-bbr.conf >/dev/null 2>&1
    local NEW_CC
    NEW_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    echo -e "${GREEN}  [✓] Algoritmo activo: ${CYAN}${NEW_CC}${NC}"
    echo -e "${GREEN}  [✓] Queue disc: ${CYAN}${QDISC}${NC}"
    press_enter
}

advanced_optimization() {
    echo -e "${CYAN}  [*] Aplicando optimización avanzada...${NC}"
    cat >> /etc/sysctl.d/99-yourvpsmaster-bbr.conf << 'SYSEOF'
# Optimización avanzada
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=6
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_max_tw_buckets=2000000
fs.file-max=1000000
net.nf_conntrack_max=1000000
SYSEOF
    sysctl -p /etc/sysctl.d/99-yourvpsmaster-bbr.conf >/dev/null 2>&1

    # Límites del sistema
    cat >> /etc/security/limits.conf << 'LIMEOF'
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
LIMEOF

    echo -e "${GREEN}  [✓] Optimización avanzada aplicada${NC}"
    press_enter
}

restore_defaults() {
    rm -f /etc/sysctl.d/99-yourvpsmaster-bbr.conf
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}  [✓] Valores por defecto restaurados${NC}"
    press_enter
}

show_network_stats() {
    clear
    echo -e "${BMAGENTA}  🍄 Estadísticas de Red  🍄${NC}"
    echo ""
    echo -e "${GREEN}  Algoritmo TCP:${NC} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    echo -e "${GREEN}  Queue Disc:${NC}    $(sysctl -n net.core.default_qdisc 2>/dev/null)"
    echo ""
    echo -e "${CYAN}  Interfaces de red:${NC}"
    ip -h link show 2>/dev/null | grep "^[0-9]" | awk '{print "  " $2}' | sed 's/://'
    echo ""
    echo -e "${CYAN}  Estadísticas TCP:${NC}"
    ss -s 2>/dev/null | head -10
    press_enter
}

bbr_menu
