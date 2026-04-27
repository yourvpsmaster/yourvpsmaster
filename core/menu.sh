#!/bin/bash
# ============================================================
#   YOURVPSMASTER - MENÚ PRINCIPAL
# ============================================================

INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

main_menu() {
    while true; do
        clear
        show_header
        show_ports
        echo ""
        echo -e "${BYELLOW}  [01]${NC} ➪ CONTROL USUARIOS (SSH/SSL/VMESS)"
        echo -e "${BYELLOW}  [02]${NC} ➪ [!] OPTIMIZAR VPS    $(port_status 0)$(config_get OPT_VPS | grep -q 1 && echo -e "${GREEN}[ON]${NC}" || echo -e "${RED}[OFF]${NC}" 2>/dev/null || echo -e "${RED}[OFF]${NC}")"
        echo -e "${BYELLOW}  [03]${NC} ➪ CONTADOR ONLINE USERS  $(config_get COUNTER_ON | grep -q 1 && echo -e "${GREEN}[ON]${NC}" || echo -e "${RED}[OFF]${NC}" 2>/dev/null || echo -e "${RED}[OFF]${NC}")"
        echo -e "${BYELLOW}  [04]${NC} ➪ AUTOINICIAR SCRIPT   $(config_get AUTOSTART | grep -q 1 && echo -e "${GREEN}[ON]${NC}" || echo -e "${RED}[OFF]${NC}" 2>/dev/null || echo -e "${GREEN}[ON]${NC}")"
        echo -e "${BYELLOW}  [05]${NC} ➪ INSTALADOR DE PROTOCOLOS"
        echo -e "${CYAN}  ─────────────────────────────────────────────────────${NC}"
        echo -e "${BRED}  [06]${NC} ➪ [!] UPDATE / REMOVE    ${YELLOW}|${NC}  ${BYELLOW}[0]${NC} ⇦ [ SALIR ]"
        echo -e "${CYAN}  ═════════════════════════════════════════════════════${NC}"
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt

        case "$opt" in
            1) bash "${INSTALL_DIR}/tools/user_control.sh" ;;
            2) bash "${INSTALL_DIR}/tools/optimize_vps.sh" ;;
            3) bash "${INSTALL_DIR}/tools/counter.sh" ;;
            4) bash "${INSTALL_DIR}/core/autostart_toggle.sh" ;;
            5) bash "${INSTALL_DIR}/core/protocols_menu.sh" ;;
            6) bash "${INSTALL_DIR}/tools/update_remove.sh" ;;
            0) clear; exit 0 ;;
            *) echo -e "${RED}  Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
