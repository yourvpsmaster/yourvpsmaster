#!/bin/bash
# YOURVPSMASTER - UPDATE / REMOVE
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

clear
show_header
echo ""
echo -e "${BMAGENTA}  🍄  UPDATE / REMOVE  🍄${NC}"
echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BYELLOW}  [1]${NC} ➪ Actualizar YourVPSMaster"
echo -e "${BRED}  [2]${NC} ➪ Desinstalar YourVPSMaster"
echo ""
echo -e "  ${BYELLOW}[0]${NC} ➪ ${BRED}[ REGRESAR ]${NC}"
echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
echo -ne "${MAGENTA}  ► Opcion : ${NC}"
read -r opt

case "$opt" in
    1)
        echo -e "${CYAN}  [*] Actualizando YourVPSMaster...${NC}"
        bash <(curl -sL https://raw.githubusercontent.com/YOURUSERNAME/yourvpsmaster/main/install.sh) 2>/dev/null
        echo -e "${GREEN}  [✓] Actualización completada${NC}"
        press_enter
        ;;
    2)
        if confirm "¿DESINSTALAR YourVPSMaster completamente?"; then
            echo -e "${RED}  [*] Desinstalando...${NC}"
            systemctl stop yourvpsmaster ws-proxy-yourvpsmaster slowdns-yourvpsmaster 2>/dev/null
            systemctl disable yourvpsmaster ws-proxy-yourvpsmaster slowdns-yourvpsmaster 2>/dev/null
            rm -f /etc/systemd/system/yourvpsmaster.service
            rm -f /etc/systemd/system/ws-proxy-yourvpsmaster.service
            rm -f /etc/systemd/system/slowdns-yourvpsmaster.service
            rm -f /usr/local/bin/yourvpsmaster
            rm -rf "${INSTALL_DIR}"
            systemctl daemon-reload
            echo -e "${GREEN}  [✓] YourVPSMaster desinstalado${NC}"
        fi
        ;;
    0) exit 0 ;;
esac
