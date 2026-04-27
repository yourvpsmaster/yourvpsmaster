#!/bin/bash
# ============================================================
#   YOURVPSMASTER - BADVPN UDP TUNNEL
# ============================================================
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

BADVPN_DIR="${INSTALL_DIR}/tools/badvpn"

badvpn_menu() {
    while true; do
        clear
        show_header
        local STATUS_7200
        STATUS_7200=$(port_status 7200)
        local STATUS_7300
        STATUS_7300=$(port_status 7300)
        echo ""
        echo -e "${BMAGENTA}  🍄  BADVPN UDP TUNNEL  🍄${NC}"
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo -e "  ${GREEN}• Puerto 7200 :${NC} ${STATUS_7200}"
        echo -e "  ${GREEN}• Puerto 7300 :${NC} ${STATUS_7300}"
        echo ""
        echo -e "${BYELLOW}  [1]${NC} ➪ Instalar BadVPN"
        echo -e "${BYELLOW}  [2]${NC} ➪ Iniciar BadVPN (puertos 7200 y 7300)"
        echo -e "${BYELLOW}  [3]${NC} ➪ Detener BadVPN"
        echo -e "${BYELLOW}  [4]${NC} ➪ Agregar puerto BadVPN custom"
        echo ""
        echo -e "  ${BYELLOW}[0]${NC} ➪ ${BRED}[ REGRESAR ]${NC}"
        echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt
        case "$opt" in
            1) install_badvpn ;;
            2) start_badvpn ;;
            3) stop_badvpn ;;
            4) add_badvpn_port ;;
            0) return ;;
        esac
    done
}

install_badvpn() {
    echo -e "${CYAN}  [*] Instalando BadVPN...${NC}"
    apt-get install -y -qq cmake make build-essential 2>/dev/null

    mkdir -p "$BADVPN_DIR"
    cd /tmp
    wget -q "https://github.com/ambrop72/badvpn/archive/refs/heads/master.zip" \
        -O badvpn.zip 2>/dev/null && \
    unzip -q badvpn.zip 2>/dev/null && \
    cd badvpn-master && \
    cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 . 2>/dev/null && \
    make 2>/dev/null && \
    cp udpgw/badvpn-udpgw "${BADVPN_DIR}/" 2>/dev/null

    if [[ ! -f "${BADVPN_DIR}/badvpn-udpgw" ]]; then
        echo -e "${YELLOW}  [!] Compilación falló, descargando binario...${NC}"
        wget -q "https://raw.githubusercontent.com/YOURUSERNAME/yourvpsmaster/main/bin/badvpn-udpgw" \
            -O "${BADVPN_DIR}/badvpn-udpgw" 2>/dev/null || {
            # Crear versión Python alternativa
            create_python_udpgw
        }
    else
        chmod +x "${BADVPN_DIR}/badvpn-udpgw"
    fi

    config_set "PROTO_BADVPN" "1"
    echo -e "${GREEN}  [✓] BadVPN instalado${NC}"
    press_enter
}

create_python_udpgw() {
    cat > "${BADVPN_DIR}/udpgw.py" << 'PYEOF'
#!/usr/bin/env python3
"""BadVPN UDPGW alternativo en Python3"""
import socket, struct, threading, sys, os

def handle(conn, addr):
    try:
        while True:
            hdr = conn.recv(2)
            if len(hdr) < 2: break
            plen = struct.unpack(">H", hdr)[0]
            if plen > 65535: break
            data = b""
            while len(data) < plen:
                chunk = conn.recv(plen - len(data))
                if not chunk: break
                data += chunk
            if len(data) < plen: break
            # Parse UDPGW packet: flags(1) + conid(2) + addr(4) + port(2) + data
            if len(data) < 9: continue
            flags = data[0]
            conid = struct.unpack(">H", data[1:3])[0]
            ip = socket.inet_ntoa(data[3:7])
            port = struct.unpack(">H", data[7:9])[0]
            payload = data[9:]
            # Forward UDP
            try:
                udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                udp.settimeout(5)
                udp.sendto(payload, (ip, port))
                resp, _ = udp.recvfrom(65536)
                udp.close()
                # Build response
                resp_data = bytes([0]) + struct.pack(">H", conid) + \
                    socket.inet_aton(ip) + struct.pack(">H", port) + resp
                resp_len = struct.pack(">H", len(resp_data))
                conn.sendall(resp_len + resp_data)
            except: pass
    except: pass
    finally: conn.close()

def server(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", port))
    s.listen(500)
    print(f"[BadVPN-PY] Escuchando en {port}", flush=True)
    while True:
        conn, addr = s.accept()
        t = threading.Thread(target=handle, args=(conn, addr), daemon=True)
        t.start()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 7300
    server(port)
PYEOF
    chmod +x "${BADVPN_DIR}/udpgw.py"
}

start_badvpn() {
    pkill -f "badvpn-udpgw" 2>/dev/null
    pkill -f "udpgw.py" 2>/dev/null

    local PORTS=(7200 7300)
    local SAVED_PORTS
    SAVED_PORTS=$(config_get "BADVPN_PORTS")
    [[ -n "$SAVED_PORTS" ]] && IFS=',' read -ra PORTS <<< "$SAVED_PORTS"

    for p in "${PORTS[@]}"; do
        if [[ -f "${BADVPN_DIR}/badvpn-udpgw" ]]; then
            nohup "${BADVPN_DIR}/badvpn-udpgw" \
                --listen-addr "0.0.0.0:${p}" \
                --max-clients 500 \
                --max-connections-for-client 10 \
                > "${LOG_DIR}/badvpn_${p}.log" 2>&1 &
        else
            nohup python3 "${BADVPN_DIR}/udpgw.py" "$p" \
                > "${LOG_DIR}/badvpn_${p}.log" 2>&1 &
        fi
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null
        echo -e "${GREEN}  [✓] BadVPN iniciado en puerto ${p}${NC}"
    done
    config_set "PROTO_BADVPN" "1"
    press_enter
}

stop_badvpn() {
    pkill -f "badvpn-udpgw" 2>/dev/null
    pkill -f "udpgw.py" 2>/dev/null
    config_set "PROTO_BADVPN" "0"
    echo -e "${RED}  [✓] BadVPN detenido${NC}"
    press_enter
}

add_badvpn_port() {
    echo -ne "${MAGENTA}  ► Nuevo puerto BadVPN: ${NC}"
    read -r NP
    [[ ! "$NP" =~ ^[0-9]+$ ]] && { echo -e "${RED}  Inválido${NC}"; sleep 2; return; }
    local CURRENT
    CURRENT=$(config_get "BADVPN_PORTS")
    [[ -z "$CURRENT" ]] && CURRENT="7200,7300"
    config_set "BADVPN_PORTS" "${CURRENT},${NP}"
    echo -e "${GREEN}  Puerto ${NP} agregado. Reinicia BadVPN para aplicar.${NC}"
    press_enter
}

badvpn_menu
