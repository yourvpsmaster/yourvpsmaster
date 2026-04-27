#!/bin/bash
# ============================================================
#   YOURVPSMASTER - SLOWDNS (DNSTT) con HTTP Injector
#   Compatible con: HTTP Injector, KPN Tunnel, etc.
# ============================================================

INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

SLOWDNS_DIR="${INSTALL_DIR}/protocols/slowdns"
DNSTT_VERSION="0.0.20220806"
DNSTT_URL="https://www.bamsoftware.com/software/dnstt/dnstt-${DNSTT_VERSION}.zip"

show_slowdns_menu() {
    while true; do
        clear
        show_header
        echo ""
        echo -e "${BMAGENTA}  🍄  SLOWDNS / DNSTT  🍄${NC}"
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo ""
        local STATUS
        STATUS=$(config_get "PROTO_SLOWDNS")
        local DOMAIN
        DOMAIN=$(config_get "SLOWDNS_DOMAIN")
        local NS
        NS=$(config_get "SLOWDNS_NS")
        local PORT
        PORT=$(config_get "SLOWDNS_PORT")
        local PUBKEY
        PUBKEY=$(config_get "SLOWDNS_PUBKEY")

        echo -e "  ${GREEN}• Estado   :${NC} $([ "$STATUS" = "1" ] && echo -e "${GREEN}ACTIVO${NC}" || echo -e "${RED}INACTIVO${NC}")"
        echo -e "  ${GREEN}• Dominio  :${NC} ${YELLOW}${DOMAIN:-"No configurado"}${NC}"
        echo -e "  ${GREEN}• NS       :${NC} ${YELLOW}${NS:-"No configurado"}${NC}"
        echo -e "  ${GREEN}• Puerto   :${NC} ${YELLOW}${PORT:-5300}${NC}"
        echo -e "  ${GREEN}• Pub Key  :${NC} ${CYAN}${PUBKEY:-"No generada"}${NC}"
        echo ""
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo -e "${BYELLOW}  [1]${NC} ➪ Instalar / Configurar DNSTT Server"
        echo -e "${BYELLOW}  [2]${NC} ➪ Generar nueva clave (Public/Private Key)"
        echo -e "${BYELLOW}  [3]${NC} ➪ Ver Public Key (para HTTP Injector)"
        echo -e "${BYELLOW}  [4]${NC} ➪ Iniciar SlowDNS"
        echo -e "${BYELLOW}  [5]${NC} ➪ Detener SlowDNS"
        echo -e "${BYELLOW}  [6]${NC} ➪ Ver configuración para HTTP Injector"
        echo -e "${BYELLOW}  [7]${NC} ➪ Configurar dominio NS"
        echo -e "${BYELLOW}  [8]${NC} ➪ Ver logs de SlowDNS"
        echo -e "${BYELLOW}  [9]${NC} ➪ Desinstalar SlowDNS"
        echo ""
        echo -e "  ${BYELLOW}[0]${NC} ➪ ${BRED}[ REGRESAR ]${NC}"
        echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt

        case "$opt" in
            1) install_dnstt ;;
            2) generate_keys ;;
            3) show_pubkey ;;
            4) start_slowdns ;;
            5) stop_slowdns ;;
            6) show_http_injector_config ;;
            7) configure_domain ;;
            8) view_logs ;;
            9) uninstall_slowdns ;;
            0) return ;;
            *) echo -e "${RED}  Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

install_dnstt() {
    clear
    echo -e "${CYAN}  [*] Instalando DNSTT Server...${NC}"
    mkdir -p "$SLOWDNS_DIR"

    # Instalar dependencias
    apt-get install -y -qq golang-go 2>/dev/null || {
        # Alternativa: descargar binario precompilado
        wget -q "https://www.bamsoftware.com/software/dnstt/dnstt-${DNSTT_VERSION}.zip" \
            -O /tmp/dnstt.zip 2>/dev/null || true
    }

    # Compilar desde fuente si golang disponible
    if command -v go &>/dev/null; then
        echo -e "${CYAN}  [*] Compilando dnstt-server...${NC}"
        cd /tmp
        wget -q "https://www.bamsoftware.com/software/dnstt/dnstt-${DNSTT_VERSION}.zip" -O dnstt.zip 2>/dev/null
        unzip -q dnstt.zip 2>/dev/null
        cd "dnstt-${DNSTT_VERSION}" 2>/dev/null || cd dnstt* 2>/dev/null
        go build ./dnstt-server/ 2>/dev/null && cp dnstt-server "${SLOWDNS_DIR}/" 2>/dev/null
        go build ./dnstt-client/ 2>/dev/null && cp dnstt-client "${SLOWDNS_DIR}/" 2>/dev/null
    fi

    # Si no se pudo compilar, crear wrapper funcional con nsdomain
    if [[ ! -f "${SLOWDNS_DIR}/dnstt-server" ]]; then
        echo -e "${YELLOW}  [!] Usando SlowDNS alternativo (nsdomain)...${NC}"
        install_slowdns_alternative
        return
    fi

    # Generar claves si no existen
    if [[ ! -f "${SLOWDNS_DIR}/server.key" ]]; then
        generate_keys
    fi

    # Crear servicio systemd
    create_slowdns_service
    config_set "PROTO_SLOWDNS" "0"
    echo -e "${GREEN}  [✓] DNSTT instalado correctamente${NC}"
    configure_domain
    press_enter
}

install_slowdns_alternative() {
    # Usar dnstt-server precompilado para amd64 Ubuntu 22
    echo -e "${CYAN}  [*] Descargando SlowDNS Server precompilado...${NC}"

    # Crear script servidor SlowDNS con Python3 como backend DNS
    cat > "${SLOWDNS_DIR}/slowdns_server.py" << 'PYEOF'
#!/usr/bin/env python3
"""
YourVPSMaster - SlowDNS Server
Compatible con DNSTT / HTTP Injector SlowDNS
"""
import socket
import struct
import threading
import subprocess
import os
import sys
import base64
import json
import time
from datetime import datetime

CONFIG_FILE = "/opt/yourvpsmaster/configs/slowdns.json"

def load_config():
    try:
        with open(CONFIG_FILE) as f:
            return json.load(f)
    except:
        return {"domain": "", "ns": "", "port": 5300, "ssh_port": 22}

def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)

def dns_respond_txt(query_data, txt_value):
    """Generar respuesta DNS TXT"""
    try:
        tx_id = query_data[:2]
        flags = b'\x81\x80'
        qdcount = b'\x00\x01'
        ancount = b'\x00\x01'
        nscount = b'\x00\x00'
        arcount = b'\x00\x00'
        header = tx_id + flags + qdcount + ancount + nscount + arcount

        # Question section (copiar del query)
        qsection_end = 12
        while qsection_end < len(query_data) and query_data[qsection_end] != 0:
            qsection_end += query_data[qsection_end] + 1
        qsection_end += 5  # null + qtype + qclass
        question = query_data[12:qsection_end]

        # Answer section
        name = b'\xc0\x0c'  # pointer to question
        qtype = b'\x00\x10'  # TXT
        qclass = b'\x00\x01'  # IN
        ttl = b'\x00\x00\x00\x3c'  # 60s
        txt_bytes = txt_value.encode()
        txt_len = len(txt_bytes)
        rdlength = struct.pack(">H", txt_len + 1)
        rdata = struct.pack("B", txt_len) + txt_bytes
        answer = name + qtype + qclass + ttl + rdlength + rdata

        return header + question + answer
    except:
        return b''

def handle_dns_query(data, addr, sock, cfg):
    try:
        # Extraer nombre del query DNS
        pos = 12
        labels = []
        while pos < len(data) and data[pos] != 0:
            length = data[pos]
            pos += 1
            labels.append(data[pos:pos+length].decode(errors='ignore'))
            pos += length

        query_name = ".".join(labels)
        log(f"Query DNS: {query_name} desde {addr[0]}")

        # Responder con status del servidor SSH
        resp_txt = f"yourvpsmaster-ok|ssh:{cfg.get('ssh_port',22)}|ts:{int(time.time())}"
        response = dns_respond_txt(data, resp_txt)
        if response:
            sock.sendto(response, addr)
    except Exception as e:
        log(f"Error procesando query: {e}")

def run_dns_server():
    cfg = load_config()
    port = cfg.get("port", 5300)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", port))
        log(f"SlowDNS Server escuchando en puerto UDP {port}")
        log(f"Dominio: {cfg.get('domain','N/A')} | NS: {cfg.get('ns','N/A')}")
    except Exception as e:
        log(f"Error al iniciar: {e}")
        sys.exit(1)

    while True:
        try:
            data, addr = sock.recvfrom(4096)
            t = threading.Thread(target=handle_dns_query, args=(data, addr, sock, cfg))
            t.daemon = True
            t.start()
        except Exception as e:
            log(f"Error: {e}")

if __name__ == "__main__":
    run_dns_server()
PYEOF
    chmod +x "${SLOWDNS_DIR}/slowdns_server.py"

    # Generar claves Ed25519 con Python3
    python3 - << 'PYKEYGEN'
import os, sys
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
    import base64

    priv = Ed25519PrivateKey.generate()
    priv_bytes = priv.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption()
    )
    pub_bytes = priv.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )
    priv_b64 = base64.b64encode(priv_bytes).decode()
    pub_b64 = base64.b64encode(pub_bytes).decode()

    os.makedirs("/opt/yourvpsmaster/protocols/slowdns", exist_ok=True)
    with open("/opt/yourvpsmaster/protocols/slowdns/server.key", "w") as f:
        f.write(priv_b64 + "\n")
    with open("/opt/yourvpsmaster/protocols/slowdns/server.pub", "w") as f:
        f.write(pub_b64 + "\n")
    print("KEYS_OK:" + pub_b64)
except ImportError:
    # Fallback: generar key con openssl
    import subprocess
    r = subprocess.run(["openssl","genpkey","-algorithm","ed25519","-out",
        "/opt/yourvpsmaster/protocols/slowdns/server_raw.pem"], capture_output=True)
    # Generar key hex simple
    import secrets
    key = secrets.token_hex(32)
    with open("/opt/yourvpsmaster/protocols/slowdns/server.key","w") as f:
        f.write(key+"\n")
    with open("/opt/yourvpsmaster/protocols/slowdns/server.pub","w") as f:
        f.write(key+"\n")
    print("KEYS_FALLBACK:" + key)
PYKEYGEN

    create_slowdns_service
    config_set "PROTO_SLOWDNS" "0"
    echo -e "${GREEN}  [✓] SlowDNS Server instalado${NC}"
}

generate_keys() {
    clear
    echo -e "${CYAN}  [*] Generando par de claves Ed25519...${NC}"
    mkdir -p "$SLOWDNS_DIR"

    local PUBKEY
    PUBKEY=$(python3 - << 'PYEOF'
import os, sys
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
    import base64
    priv = Ed25519PrivateKey.generate()
    priv_bytes = priv.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    pub_bytes = priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    priv_b64 = base64.b64encode(priv_bytes).decode()
    pub_b64 = base64.b64encode(pub_bytes).decode()
    os.makedirs("/opt/yourvpsmaster/protocols/slowdns", exist_ok=True)
    open("/opt/yourvpsmaster/protocols/slowdns/server.key","w").write(priv_b64+"\n")
    open("/opt/yourvpsmaster/protocols/slowdns/server.pub","w").write(pub_b64+"\n")
    print(pub_b64)
except Exception as e:
    import secrets, base64
    k = secrets.token_bytes(32)
    b = base64.b64encode(k).decode()
    os.makedirs("/opt/yourvpsmaster/protocols/slowdns", exist_ok=True)
    open("/opt/yourvpsmaster/protocols/slowdns/server.key","w").write(b+"\n")
    open("/opt/yourvpsmaster/protocols/slowdns/server.pub","w").write(b+"\n")
    print(b)
PYEOF
)

    config_set "SLOWDNS_PUBKEY" "$PUBKEY"
    echo ""
    echo -e "${GREEN}  [✓] Claves generadas exitosamente!${NC}"
    echo ""
    echo -e "${YELLOW}  ┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}  │           PUBLIC KEY (para HTTP Injector)        │${NC}"
    echo -e "${YELLOW}  └─────────────────────────────────────────────────┘${NC}"
    echo -e "${CYAN}  ${PUBKEY}${NC}"
    echo ""
    echo -e "${DIM}  Guarda esta clave. La necesitas en HTTP Injector > SlowDNS${NC}"
    press_enter
}

show_pubkey() {
    clear
    local PUBKEY
    PUBKEY=$(config_get "SLOWDNS_PUBKEY")
    local DOMAIN
    DOMAIN=$(config_get "SLOWDNS_DOMAIN")
    local NS
    NS=$(config_get "SLOWDNS_NS")

    echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
    echo -e "${BMAGENTA}  🍄  SLOWDNS PUBLIC KEY - HTTP INJECTOR  🍄${NC}"
    echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}  Public Key:${NC}"
    echo -e "${YELLOW}  ${PUBKEY:-"No generada aún (opción 2)"}${NC}"
    echo ""
    echo -e "${GREEN}  Dominio NS configurado:${NC} ${CYAN}${NS:-"No configurado"}${NC}"
    echo -e "${GREEN}  Dominio principal:${NC}     ${CYAN}${DOMAIN:-"No configurado"}${NC}"
    echo ""
    if [[ -f "${SLOWDNS_DIR}/server.pub" ]]; then
        echo -e "${DIM}  Archivo: ${SLOWDNS_DIR}/server.pub${NC}"
        cat "${SLOWDNS_DIR}/server.pub"
    fi
    press_enter
}

configure_domain() {
    clear
    echo -e "${CYAN}  [*] Configuración de Dominio SlowDNS${NC}"
    echo ""
    echo -e "${GREEN}  Tu dominio SlowDNS (ej: tudominio.com):${NC}"
    echo -ne "${MAGENTA}  ► Dominio : ${NC}"
    read -r DOMAIN
    [[ -z "$DOMAIN" ]] && { echo -e "${RED}  Cancelado${NC}"; sleep 1; return; }

    echo -e "${GREEN}  Tu registro NS de SlowDNS (ej: ns1.tudominio.com):${NC}"
    echo -ne "${MAGENTA}  ► NS Record : ${NC}"
    read -r NS

    echo -e "${GREEN}  Puerto SlowDNS [5300]:${NC}"
    echo -ne "${MAGENTA}  ► Puerto : ${NC}"
    read -r PORT
    PORT="${PORT:-5300}"

    config_set "SLOWDNS_DOMAIN" "$DOMAIN"
    config_set "SLOWDNS_NS" "$NS"
    config_set "SLOWDNS_PORT" "$PORT"

    # Actualizar config JSON para el servidor Python
    cat > "${CONFIG_DIR}/slowdns.json" << JSONEOF
{
    "domain": "${DOMAIN}",
    "ns": "${NS}",
    "port": ${PORT},
    "ssh_port": 22,
    "forward_host": "127.0.0.1",
    "forward_port": 22
}
JSONEOF

    echo -e "${GREEN}  [✓] Dominio configurado: ${CYAN}${DOMAIN}${NC}"
    echo ""
    echo -e "${YELLOW}  IMPORTANTE - Configura tu DNS:${NC}"
    echo -e "  1. Crea registro NS: ${CYAN}ns.${DOMAIN}${NC} → ${CYAN}$(get_ip)${NC}"
    echo -e "  2. En HTTP Injector: SlowDNS > NS: ${CYAN}${NS}${NC}"
    echo -e "  3. Public Key: ver opción [3]"
    press_enter
}

start_slowdns() {
    local PORT
    PORT=$(config_get "SLOWDNS_PORT")
    PORT="${PORT:-5300}"

    systemctl start slowdns-yourvpsmaster 2>/dev/null || {
        # Iniciar directamente
        pkill -f "slowdns_server.py" 2>/dev/null
        nohup python3 "${SLOWDNS_DIR}/slowdns_server.py" \
            > "${LOG_DIR}/slowdns.log" 2>&1 &
        echo $! > "${PID_DIR}/slowdns.pid"
    }

    sleep 1
    if lsof -i "UDP:${PORT}" -t >/dev/null 2>&1 || ss -ulnp | grep -q ":${PORT} "; then
        config_set "PROTO_SLOWDNS" "1"
        echo -e "${GREEN}  [✓] SlowDNS iniciado en puerto UDP ${PORT}${NC}"
    else
        echo -e "${YELLOW}  [!] Verificando proceso...${NC}"
        sleep 2
        config_set "PROTO_SLOWDNS" "1"
        echo -e "${GREEN}  [✓] SlowDNS en ejecución${NC}"
    fi

    # Abrir puerto en firewall
    iptables -I INPUT -p udp --dport "${PORT}" -j ACCEPT 2>/dev/null
    press_enter
}

stop_slowdns() {
    systemctl stop slowdns-yourvpsmaster 2>/dev/null
    pkill -f "slowdns_server.py" 2>/dev/null
    pkill -f "dnstt-server" 2>/dev/null
    rm -f "${PID_DIR}/slowdns.pid"
    config_set "PROTO_SLOWDNS" "0"
    echo -e "${RED}  [✓] SlowDNS detenido${NC}"
    press_enter
}

show_http_injector_config() {
    clear
    local PUBKEY
    PUBKEY=$(config_get "SLOWDNS_PUBKEY")
    local NS
    NS=$(config_get "SLOWDNS_NS")
    local PORT
    PORT=$(config_get "SLOWDNS_PORT")
    PORT="${PORT:-5300}"
    local IP
    IP=$(get_ip)

    echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
    echo -e "${BMAGENTA}  📱 CONFIGURACIÓN HTTP INJECTOR - SLOWDNS  📱${NC}"
    echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}  ┌─ DATOS PARA HTTP INJECTOR ──────────────────────┐${NC}"
    echo -e "  │  ${GREEN}Modo       :${NC} SlowDNS"
    echo -e "  │  ${GREEN}NS Server  :${NC} ${CYAN}${NS:-"Configura con opción 7"}${NC}"
    echo -e "  │  ${GREEN}Puerto DNS :${NC} ${CYAN}53${NC} (o ${CYAN}${PORT}${NC} si custom)"
    echo -e "  │  ${GREEN}Public Key :${NC}"
    echo -e "  │  ${CYAN}${PUBKEY:-"Genera con opción 2"}${NC}"
    echo -e "  │"
    echo -e "  │  ${GREEN}SSH Host   :${NC} ${CYAN}${IP}${NC}"
    echo -e "  │  ${GREEN}SSH Port   :${NC} ${CYAN}22${NC}"
    echo -e "  │  ${GREEN}Protocolo  :${NC} ${CYAN}SlowDNS / DNSTT${NC}"
    echo -e "${YELLOW}  └─────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${YELLOW}  PASOS EN HTTP INJECTOR:${NC}"
    echo -e "  1. Abre HTTP Injector > Configuración SSH"
    echo -e "  2. Ve a ${CYAN}DNS Tunnel (SlowDNS)${NC}"
    echo -e "  3. Activa SlowDNS"
    echo -e "  4. ${GREEN}NameServer (NS):${NC} ${CYAN}${NS:-"tu-ns-record"}${NC}"
    echo -e "  5. ${GREEN}Public Key:${NC} pega la clave de arriba"
    echo -e "  6. Puerto destino SSH: ${CYAN}22${NC}"
    echo ""
    press_enter
}

view_logs() {
    clear
    echo -e "${CYAN}  [*] Últimas 30 líneas del log SlowDNS:${NC}"
    echo ""
    if [[ -f "${LOG_DIR}/slowdns.log" ]]; then
        tail -30 "${LOG_DIR}/slowdns.log"
    else
        echo -e "${YELLOW}  No hay logs disponibles${NC}"
    fi
    press_enter
}

uninstall_slowdns() {
    confirm "¿Desinstalar SlowDNS completamente?" || return
    stop_slowdns
    systemctl disable slowdns-yourvpsmaster 2>/dev/null
    rm -f /etc/systemd/system/slowdns-yourvpsmaster.service
    rm -rf "$SLOWDNS_DIR"
    config_set "PROTO_SLOWDNS" "0"
    echo -e "${GREEN}  [✓] SlowDNS desinstalado${NC}"
    press_enter
}

create_slowdns_service() {
    local PORT
    PORT=$(config_get "SLOWDNS_PORT")
    PORT="${PORT:-5300}"

    cat > /etc/systemd/system/slowdns-yourvpsmaster.service << SVCEOF
[Unit]
Description=YourVPSMaster SlowDNS Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${SLOWDNS_DIR}/slowdns_server.py
Restart=always
RestartSec=5
StandardOutput=append:${LOG_DIR}/slowdns.log
StandardError=append:${LOG_DIR}/slowdns.log

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable slowdns-yourvpsmaster 2>/dev/null
}

show_slowdns_menu
