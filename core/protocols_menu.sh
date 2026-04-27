#!/bin/bash
# ============================================================
#   YOURVPSMASTER - MENÚ DE PROTOCOLOS
# ============================================================

INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

get_proto_status() {
    local name="$1"
    config_get "PROTO_${name}" | grep -q "1" && echo -e "${GREEN}[ON]${NC}" || echo -e "${RED}[OFF]${NC}"
}

protocols_menu() {
    while true; do
        clear
        show_header
        echo ""
        echo -e "${BMAGENTA}  🍄  INSTALACION DE PROTOCOLOS  🍄${NC}"
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo ""
        printf "  ${BYELLOW}[1]${NC}  ➪ %-20s %s    ${BYELLOW}[11]${NC} ➪ %-18s %s\n" \
            "OpenSSH"         "$(get_proto_status SSH)" \
            "PSIPHON SERVER"  "$(get_proto_status PSIPHON)"
        printf "  ${BYELLOW}[2]${NC}  ➪ %-20s %s    ${BYELLOW}[12]${NC} ➪ %-18s %s\n" \
            "DROPBEAR"        "$(get_proto_status DROPBEAR)" \
            "TCP DNS"         "${CYAN}(#BETA)${NC}"
        printf "  ${BYELLOW}[3]${NC}  ➪ %-20s %s    ${BYELLOW}[13]${NC} ➪ %-18s %s\n" \
            "OPENVPN"         "$(get_proto_status OPENVPN)" \
            "WEBMIN"          "$(get_proto_status WEBMIN)"
        printf "  ${BYELLOW}[4]${NC}  ➪ %-20s %s    ${BYELLOW}[14]${NC} ➪ %-18s %s\n" \
            "SSL/TLS"         "$(get_proto_status SSL)" \
            "SlowDNS"         "$(get_proto_status SLOWDNS)"
        printf "  ${BYELLOW}[5]${NC}  ➪ %-20s %s    ${BYELLOW}[15]${NC} ➪ %-18s %s\n" \
            "SHADOWSOCKS-R"   "$(get_proto_status SSR)" \
            "SSL->PYTHON"     "$(get_proto_status SSLPYTHON)"
        printf "  ${BYELLOW}[6]${NC}  ➪ %-20s %s    ${BYELLOW}[16]${NC} ➪ %-18s %s\n" \
            "SQUID"           "$(get_proto_status SQUID)" \
            "SSLH Multiplex"  "$(get_proto_status SSLH)"
        printf "  ${BYELLOW}[7]${NC}  ➪ %-20s %-8s  ${BYELLOW}[17]${NC} ➪ %-18s %s\n" \
            "PROXY PYTHON"    "${CYAN}[PyD]${NC}" \
            "OVER WEBSOCKET"  "${CYAN}(#BETA)${NC}"
        printf "  ${BYELLOW}[8]${NC}  ➪ %-20s %-8s  ${BYELLOW}[18]${NC} ➪ %-18s %s\n" \
            "V2RAY SWITCH"    "${CYAN}[UI]${NC}" \
            "SOCKS5"          "${CYAN}(#BETA)${NC}"
        printf "  ${BYELLOW}[9]${NC}  ➪ %-20s %s    ${BYELLOW}[19]${NC} ➪ %-18s %s\n" \
            "CFA (CLASH)"     "$(get_proto_status CLASH)" \
            "Protocolos UDP"  "$(get_proto_status UDP)"
        printf "  ${BYELLOW}[10]${NC} ➪ %-20s %s    ${BYELLOW}[20]${NC} ➪ %-18s\n" \
            "TROJAN-GO"       "$(get_proto_status TROJAN)" \
            "${CYAN}FUNCIONES EN DISEÑO!${NC}"
        echo ""
        echo -e "${BMAGENTA}  🍄  INSTALACION DE HERRAMIENTAS Y SERVICIOS  🍄${NC}"
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo ""
        printf "  ${BYELLOW}[21]${NC} ➪ %-22s  ${BYELLOW}[22]${NC} ➪ %-15s %s\n" \
            "BLOCK TORRENT" \
            "BadVPN"  "$(get_proto_status BADVPN)"
        printf "  ${BYELLOW}[23]${NC} ➪ %-22s  ${BYELLOW}[24]${NC} ➪ %-15s %s\n" \
            "TCP (BBR|Plus) ${GREEN}[ON]${NC}" \
            "FAILBAN"  "$(get_proto_status FAILBAN)"
        printf "  ${BYELLOW}[25]${NC} ➪ %-22s  ${BYELLOW}[26]${NC} ➪ %-15s\n" \
            "ARCHIVO ONLINE ${GREEN}[81]${NC}" \
            "UP|DOWN SpeedTest"
        printf "  ${BYELLOW}[27]${NC} ➪ %-22s  ${BYELLOW}[28]${NC} ➪ %-15s %s\n" \
            "DETALLES DEL VPS" \
            "Block ADS"  "$(get_proto_status BLOCKADS)"
        printf "  ${BYELLOW}[29]${NC} ➪ %-22s  ${BYELLOW}[30]${NC} ➪ %-15s\n" \
            "DNS CUSTOM (NETFLIX)" \
            "HERRAMIENTAS EXTRAS"
        printf "  ${BYELLOW}[31]${NC} ➪ %-22s  ${BYELLOW}[32]${NC} ➪ %-15s %s\n" \
            "REINICIAR SERVICIOS" \
            "Brook Server"  "$(get_proto_status BROOK)"
        printf "  ${BYELLOW}[33]${NC} ➪ %-22s  ${BYELLOW}[34]${NC} ➪ %-15s\n" \
            "FIREWALL (IPTABLES)" \
            "Enable/Change PASSWD ROOT"
        echo ""
        printf "  ${BYELLOW}[35]${NC} ➪ %-22s  ${BYELLOW}[0]${NC}  ➪ ${BRED}[ REGRESAR ]${NC}\n" \
            "AToken [APP's Mods]"
        echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt

        case "$opt" in
            1)  bash "${INSTALL_DIR}/protocols/openssh.sh" ;;
            2)  bash "${INSTALL_DIR}/protocols/dropbear.sh" ;;
            3)  bash "${INSTALL_DIR}/protocols/openvpn.sh" ;;
            4)  bash "${INSTALL_DIR}/protocols/ssl_tls.sh" ;;
            5)  bash "${INSTALL_DIR}/protocols/shadowsocks.sh" ;;
            6)  bash "${INSTALL_DIR}/protocols/squid.sh" ;;
            7)  bash "${INSTALL_DIR}/protocols/proxy_python.sh" ;;
            8)  bash "${INSTALL_DIR}/protocols/v2ray.sh" ;;
            9)  bash "${INSTALL_DIR}/protocols/clash.sh" ;;
            10) bash "${INSTALL_DIR}/protocols/trojan.sh" ;;
            11) bash "${INSTALL_DIR}/protocols/psiphon.sh" ;;
            12) echo -e "${CYAN}TCP DNS - Próximamente (BETA)${NC}"; sleep 2 ;;
            13) bash "${INSTALL_DIR}/tools/webmin.sh" ;;
            14) bash "${INSTALL_DIR}/protocols/slowdns.sh" ;;
            15) bash "${INSTALL_DIR}/protocols/ssl_python.sh" ;;
            16) bash "${INSTALL_DIR}/protocols/sslh.sh" ;;
            17) echo -e "${CYAN}Over WebSocket - Próximamente (BETA)${NC}"; sleep 2 ;;
            18) bash "${INSTALL_DIR}/protocols/socks5.sh" ;;
            19) bash "${INSTALL_DIR}/protocols/udp_proto.sh" ;;
            20) echo -e "${CYAN}Funciones en diseño...${NC}"; sleep 2 ;;
            21) bash "${INSTALL_DIR}/tools/block_torrent.sh" ;;
            22) bash "${INSTALL_DIR}/tools/badvpn.sh" ;;
            23) bash "${INSTALL_DIR}/tools/bbr.sh" ;;
            24) bash "${INSTALL_DIR}/tools/fail2ban.sh" ;;
            25) bash "${INSTALL_DIR}/tools/file_manager.sh" ;;
            26) bash "${INSTALL_DIR}/tools/speedtest.sh" ;;
            27) bash "${INSTALL_DIR}/tools/vps_info.sh" ;;
            28) bash "${INSTALL_DIR}/tools/block_ads.sh" ;;
            29) bash "${INSTALL_DIR}/tools/dns_custom.sh" ;;
            30) bash "${INSTALL_DIR}/tools/extras.sh" ;;
            31) bash "${INSTALL_DIR}/tools/restart_services.sh" ;;
            32) bash "${INSTALL_DIR}/protocols/brook.sh" ;;
            33) bash "${INSTALL_DIR}/tools/firewall.sh" ;;
            34) bash "${INSTALL_DIR}/tools/change_passwd.sh" ;;
            35) bash "${INSTALL_DIR}/tools/atoken.sh" ;;
            0)  return ;;
            *)  echo -e "${RED}  Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

protocols_menu
