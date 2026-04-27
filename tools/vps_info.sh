#!/bin/bash
# YOURVPSMASTER - VPS INFO
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

clear
show_header
echo ""
echo -e "${BMAGENTA}  🍄  DETALLES DEL VPS  🍄${NC}"
echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}  Sistema Operativo:${NC} $(cat /etc/os-release | grep PRETTY | cut -d= -f2 | tr -d '"')"
echo -e "${GREEN}  Kernel:${NC}            $(uname -r)"
echo -e "${GREEN}  Arquitectura:${NC}     $(uname -m)"
echo -e "${GREEN}  Hostname:${NC}          $(hostname)"
echo -e "${GREEN}  IP Pública:${NC}        $(get_ip)"
echo -e "${GREEN}  IP Local:${NC}          $(hostname -I | awk '{print $1}')"
echo ""
echo -e "${GREEN}  CPU Modelo:${NC}        $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
echo -e "${GREEN}  CPU Cores:${NC}         $(nproc)"
echo -e "${GREEN}  CPU Uso:${NC}           $(get_cpu_pct)"
echo ""
echo -e "${GREEN}  RAM Total:${NC}         $(free -h | awk '/Mem:/{print $2}')"
echo -e "${GREEN}  RAM Libre:${NC}         $(free -h | awk '/Mem:/{print $4}')"
echo -e "${GREEN}  RAM Uso:${NC}           $(free -h | awk '/Mem:/{print $3}')"
echo ""
echo -e "${GREEN}  Disco Total:${NC}       $(df -h / | awk 'NR==2{print $2}')"
echo -e "${GREEN}  Disco Libre:${NC}       $(df -h / | awk 'NR==2{print $4}')"
echo -e "${GREEN}  Disco Uso:${NC}         $(df -h / | awk 'NR==2{print $5}')"
echo ""
echo -e "${GREEN}  Uptime:${NC}            $(uptime -p)"
echo -e "${GREEN}  Carga sistema:${NC}     $(uptime | awk -F'load average:' '{print $2}')"
echo ""
echo -e "${YELLOW}  ════ Puertos Abiertos ════${NC}"
ss -tlnp 2>/dev/null | awk 'NR>1{print "  " $4}' | sed 's/.*:/  Puerto: /' | head -20
press_enter
