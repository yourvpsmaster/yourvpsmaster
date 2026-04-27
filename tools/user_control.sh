#!/bin/bash
# ============================================================
#   YOURVPSMASTER - CONTROL DE USUARIOS
# ============================================================
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

user_control_menu() {
    while true; do
        clear
        show_header
        echo ""
        echo -e "${BMAGENTA}  🍄  CONTROL USUARIOS (SSH/SSL/VMESS)  🍄${NC}"
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${BYELLOW}  [1]${NC} ➪ Crear usuario SSH"
        echo -e "${BYELLOW}  [2]${NC} ➪ Eliminar usuario SSH"
        echo -e "${BYELLOW}  [3]${NC} ➪ Ver usuarios activos (online)"
        echo -e "${BYELLOW}  [4]${NC} ➪ Ver todos los usuarios SSH"
        echo -e "${BYELLOW}  [5]${NC} ➪ Renovar expiración de usuario"
        echo -e "${BYELLOW}  [6]${NC} ➪ Bloquear / Desbloquear usuario"
        echo -e "${BYELLOW}  [7]${NC} ➪ Cambiar contraseña de usuario"
        echo -e "${BYELLOW}  [8]${NC} ➪ Límite de conexiones por usuario"
        echo ""
        echo -e "  ${BYELLOW}[0]${NC} ➪ ${BRED}[ REGRESAR ]${NC}"
        echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt

        case "$opt" in
            1) create_user ;;
            2) delete_user ;;
            3) show_online_users ;;
            4) list_users ;;
            5) renew_user ;;
            6) toggle_user ;;
            7) change_user_pass ;;
            8) set_user_limit ;;
            0) return ;;
            *) echo -e "${RED}  Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

create_user() {
    clear
    echo -e "${BMAGENTA}  🍄 Crear Usuario SSH  🍄${NC}"
    echo ""
    echo -ne "${MAGENTA}  ► Usuario: ${NC}"
    read -r UNAME
    [[ -z "$UNAME" ]] && return

    echo -ne "${MAGENTA}  ► Contraseña: ${NC}"
    read -r UPASS
    [[ -z "$UPASS" ]] && return

    echo -ne "${MAGENTA}  ► Días de expiración [30]: ${NC}"
    read -r UDAYS
    UDAYS="${UDAYS:-30}"

    local UEXP
    UEXP=$(date -d "+${UDAYS} days" +%Y-%m-%d)

    if id "$UNAME" &>/dev/null; then
        echo -e "${YELLOW}  [!] El usuario ${UNAME} ya existe${NC}"
    else
        useradd -e "$UEXP" -s /bin/false -M "$UNAME" 2>/dev/null
        echo "${UNAME}:${UPASS}" | chpasswd
        echo -e "${GREEN}  [✓] Usuario ${UNAME} creado${NC}"
    fi

    local IP
    IP=$(get_ip)
    local SSH_PORT
    SSH_PORT=$(config_get "SSH_PORT" || echo "22")
    local WS_PORTS
    WS_PORTS=$(python3 -c "import json; d=json.load(open('/opt/yourvpsmaster/configs/ws_proxy.json')); print(d['ports'][0])" 2>/dev/null || echo "80")

    echo ""
    echo -e "${YELLOW}  ┌─ DATOS DE ACCESO ───────────────────────────────┐${NC}"
    echo -e "  │  ${GREEN}Usuario    :${NC} ${CYAN}${UNAME}${NC}"
    echo -e "  │  ${GREEN}Contraseña :${NC} ${CYAN}${UPASS}${NC}"
    echo -e "  │  ${GREEN}Host       :${NC} ${CYAN}${IP}${NC}"
    echo -e "  │  ${GREEN}Puerto SSH :${NC} ${CYAN}${SSH_PORT}${NC}"
    echo -e "  │  ${GREEN}Puerto WS  :${NC} ${CYAN}${WS_PORTS}${NC}"
    echo -e "  │  ${GREEN}Expira     :${NC} ${YELLOW}${UEXP}${NC} (${UDAYS} días)"
    echo -e "${YELLOW}  └─────────────────────────────────────────────────┘${NC}"
    press_enter
}

delete_user() {
    echo -ne "${MAGENTA}  ► Usuario a eliminar: ${NC}"
    read -r UNAME
    [[ -z "$UNAME" ]] && return
    confirm "¿Eliminar usuario ${UNAME}?" || return
    pkill -u "$UNAME" 2>/dev/null
    userdel -f "$UNAME" 2>/dev/null
    echo -e "${GREEN}  [✓] Usuario ${UNAME} eliminado${NC}"
    press_enter
}

show_online_users() {
    clear
    echo -e "${BMAGENTA}  🍄 Usuarios SSH Conectados Ahora  🍄${NC}"
    echo ""
    echo -e "${CYAN}  Usuario         IP Remota       Tiempo${NC}"
    echo -e "${YELLOW}  ─────────────────────────────────────────${NC}"
    who | awk '{printf "  %-15s %-15s %s %s\n", $1, $5, $3, $4}' | sed 's/[()]//g'
    echo ""
    echo -e "${GREEN}  Total online: $(who | wc -l)${NC}"
    press_enter
}

list_users() {
    clear
    echo -e "${BMAGENTA}  🍄 Usuarios SSH del Sistema  🍄${NC}"
    echo ""
    echo -e "${CYAN}  Usuario         Shell           Expira${NC}"
    echo -e "${YELLOW}  ─────────────────────────────────────────────────${NC}"
    while IFS=: read -r user _ uid _ _ _ shell; do
        [[ "$uid" -lt 1000 ]] && continue
        [[ "$shell" == "/bin/false" || "$shell" == "/usr/sbin/nologin" ]] || continue
        local exp
        exp=$(chage -l "$user" 2>/dev/null | grep "Account expires" | awk -F: '{print $2}' | xargs)
        printf "  %-15s %-15s %s\n" "$user" "$shell" "$exp"
    done < /etc/passwd
    press_enter
}

renew_user() {
    echo -ne "${MAGENTA}  ► Usuario: ${NC}"
    read -r UNAME
    echo -ne "${MAGENTA}  ► Nuevos días: ${NC}"
    read -r DAYS
    local NEW_EXP
    NEW_EXP=$(date -d "+${DAYS} days" +%Y-%m-%d)
    chage -E "$NEW_EXP" "$UNAME" 2>/dev/null
    echo -e "${GREEN}  [✓] ${UNAME} renovado hasta ${NEW_EXP}${NC}"
    press_enter
}

toggle_user() {
    echo -ne "${MAGENTA}  ► Usuario: ${NC}"
    read -r UNAME
    echo -e "${BYELLOW}  [1]${NC} Bloquear  ${BYELLOW}[2]${NC} Desbloquear"
    echo -ne "${MAGENTA}  ► Opción: ${NC}"
    read -r A
    case "$A" in
        1) passwd -l "$UNAME" 2>/dev/null; echo -e "${RED}  [✓] ${UNAME} bloqueado${NC}" ;;
        2) passwd -u "$UNAME" 2>/dev/null; echo -e "${GREEN}  [✓] ${UNAME} desbloqueado${NC}" ;;
    esac
    press_enter
}

change_user_pass() {
    echo -ne "${MAGENTA}  ► Usuario: ${NC}"
    read -r UNAME
    echo -ne "${MAGENTA}  ► Nueva contraseña: ${NC}"
    read -r NPASS
    echo "${UNAME}:${NPASS}" | chpasswd 2>/dev/null
    echo -e "${GREEN}  [✓] Contraseña actualizada${NC}"
    press_enter
}

set_user_limit() {
    echo -ne "${MAGENTA}  ► Usuario: ${NC}"
    read -r UNAME
    echo -ne "${MAGENTA}  ► Máximo de conexiones simultáneas: ${NC}"
    read -r MAXCONN
    # Implementar via PAM o monitoreo
    config_set "USER_LIMIT_${UNAME}" "$MAXCONN"
    echo -e "${GREEN}  [✓] Límite de ${MAXCONN} conexiones para ${UNAME}${NC}"
    press_enter
}

user_control_menu
