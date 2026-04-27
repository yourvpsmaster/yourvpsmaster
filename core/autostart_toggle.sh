#!/bin/bash
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"
CURRENT=$(config_get "AUTOSTART")
if [[ "$CURRENT" == "1" ]]; then
    config_set "AUTOSTART" "0"
    systemctl disable yourvpsmaster 2>/dev/null
    echo -e "${RED}  [✓] AutoStart DESACTIVADO${NC}"
else
    config_set "AUTOSTART" "1"
    systemctl enable yourvpsmaster 2>/dev/null
    echo -e "${GREEN}  [✓] AutoStart ACTIVADO${NC}"
fi
press_enter
