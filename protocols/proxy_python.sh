#!/bin/bash
# ============================================================
#   YOURVPSMASTER - PROXY PYTHON3 WEBSOCKET
#   Soporta múltiples puertos + respuesta HTTP 101
# ============================================================

INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

WS_DIR="${INSTALL_DIR}/protocols/ws_python"

# Servidor WebSocket Python3 con soporte HTTP 101
create_ws_server() {
    mkdir -p "$WS_DIR"
    cat > "${WS_DIR}/ws_proxy.py" << 'PYEOF'
#!/usr/bin/env python3
"""
YourVPSMaster - WebSocket/HTTP Proxy Server
Soporta:
  - HTTP 101 Switching Protocols (WebSocket Upgrade)
  - HTTP CONNECT (túnel directo)
  - Múltiples puertos simultáneos
  - Compatible con HTTP Injector, KPN Tunnel, HA Tunnel
"""

import asyncio
import socket
import ssl
import sys
import os
import json
import signal
import logging
from datetime import datetime

CONFIG_FILE = "/opt/yourvpsmaster/configs/ws_proxy.json"
LOG_FILE = "/opt/yourvpsmaster/logs/ws_proxy.log"
PID_DIR = "/opt/yourvpsmaster/pids"

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
log = logging.getLogger("ws_proxy")

def load_config():
    defaults = {
        "ports": [80, 8080, 3128],
        "ssh_host": "127.0.0.1",
        "ssh_port": 22,
        "response_101": True,
        "custom_response": "",
        "buffer_size": 65536
    }
    try:
        with open(CONFIG_FILE) as f:
            cfg = json.load(f)
            defaults.update(cfg)
    except:
        pass
    return defaults

# ────────────────────────────────────────────
#  Respuestas HTTP personalizables
# ────────────────────────────────────────────
HTTP_101 = (
    "HTTP/1.1 101 Switching Protocols\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    "\r\n"
).encode()

HTTP_200 = (
    "HTTP/1.1 200 Connection Established\r\n"
    "\r\n"
).encode()

HTTP_200_OK = (
    "HTTP/1.1 200 OK\r\n"
    "Content-Length: 0\r\n"
    "Connection: keep-alive\r\n"
    "\r\n"
).encode()

def make_custom_response(template: str) -> bytes:
    """Generar respuesta custom. Template puede incluir [crlf] y [lfcr]"""
    if not template:
        return HTTP_101
    result = template.replace("[crlf]", "\r\n").replace("[lfcr]", "\n\r")
    return result.encode()

# ────────────────────────────────────────────
#  Pipe bidireccional entre cliente y SSH
# ────────────────────────────────────────────
async def pipe(reader, writer, label=""):
    try:
        buf_size = 65536
        while True:
            data = await asyncio.wait_for(reader.read(buf_size), timeout=300)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (asyncio.TimeoutError, ConnectionResetError, BrokenPipeError):
        pass
    except Exception as e:
        pass
    finally:
        try:
            writer.close()
        except:
            pass

# ────────────────────────────────────────────
#  Manejar conexión entrante
# ────────────────────────────────────────────
async def handle_client(reader, writer, cfg):
    addr = writer.get_extra_info('peername', ('?', 0))
    client_ip = addr[0]

    try:
        # Leer cabecera HTTP
        header_data = b""
        while b"\r\n\r\n" not in header_data:
            chunk = await asyncio.wait_for(reader.read(4096), timeout=10)
            if not chunk:
                writer.close()
                return
            header_data += chunk
            if len(header_data) > 8192:
                break

        header_str = header_data.decode(errors='ignore')
        first_line = header_str.split('\r\n')[0] if header_str else ""

        log.info(f"[{client_ip}] {first_line[:80]}")

        ssh_host = cfg.get("ssh_host", "127.0.0.1")
        ssh_port = cfg.get("ssh_port", 22)

        # Conectar al servidor SSH destino
        try:
            ssh_reader, ssh_writer = await asyncio.wait_for(
                asyncio.open_connection(ssh_host, ssh_port),
                timeout=10
            )
        except Exception as e:
            log.warning(f"[{client_ip}] No se pudo conectar a SSH {ssh_host}:{ssh_port} - {e}")
            writer.close()
            return

        # Determinar tipo de request y enviar respuesta apropiada
        custom_resp = cfg.get("custom_response", "")

        if "CONNECT" in first_line:
            # HTTP CONNECT → responder 200 y tunelizar
            response = HTTP_200
        elif "Upgrade: websocket" in header_str or "upgrade: websocket" in header_str.lower():
            # WebSocket Upgrade → responder 101
            response = make_custom_response(custom_resp) if custom_resp else HTTP_101
        else:
            # Request genérico → responder 101 (para HTTP Injector)
            response = make_custom_response(custom_resp) if custom_resp else HTTP_101

        writer.write(response)
        await writer.drain()

        # Cualquier dato extra tras la cabecera va al SSH
        extra = header_data.split(b"\r\n\r\n", 1)
        if len(extra) > 1 and extra[1]:
            ssh_writer.write(extra[1])
            await ssh_writer.drain()

        # Iniciar pipe bidireccional
        await asyncio.gather(
            pipe(reader, ssh_writer, f"client→ssh"),
            pipe(ssh_reader, writer, f"ssh→client"),
            return_exceptions=True
        )

    except Exception as e:
        log.error(f"[{client_ip}] Error: {e}")
    finally:
        try:
            writer.close()
        except:
            pass

# ────────────────────────────────────────────
#  Iniciar servidor en un puerto
# ────────────────────────────────────────────
async def start_server_on_port(port, cfg):
    try:
        server = await asyncio.start_server(
            lambda r, w: handle_client(r, w, cfg),
            "0.0.0.0",
            port,
            reuse_address=True,
            reuse_port=True
        )
        log.info(f"[✓] Puerto WebSocket activo: {port}")
        return server
    except Exception as e:
        log.error(f"[✗] Error al abrir puerto {port}: {e}")
        return None

# ────────────────────────────────────────────
#  Main
# ────────────────────────────────────────────
async def main():
    cfg = load_config()
    ports = cfg.get("ports", [80, 8080, 3128])

    log.info("=" * 50)
    log.info("  YourVPSMaster - WebSocket Proxy Server")
    log.info(f"  Puertos: {ports}")
    log.info(f"  SSH destino: {cfg['ssh_host']}:{cfg['ssh_port']}")
    log.info("=" * 50)

    servers = []
    for port in ports:
        srv = await start_server_on_port(port, cfg)
        if srv:
            servers.append(srv)

    if not servers:
        log.error("No se pudo iniciar ningún servidor")
        sys.exit(1)

    # Guardar PID
    os.makedirs(PID_DIR, exist_ok=True)
    with open(f"{PID_DIR}/ws_proxy.pid", "w") as f:
        f.write(str(os.getpid()))

    async with asyncio.gather(*[s.serve_forever() for s in servers], return_exceptions=True):
        pass

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Servidor detenido")
PYEOF
    chmod +x "${WS_DIR}/ws_proxy.py"
}

create_ws_service() {
    cat > /etc/systemd/system/ws-proxy-yourvpsmaster.service << SVCEOF
[Unit]
Description=YourVPSMaster WebSocket Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${WS_DIR}/ws_proxy.py
Restart=always
RestartSec=5
StandardOutput=append:${LOG_DIR}/ws_proxy.log
StandardError=append:${LOG_DIR}/ws_proxy.log

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable ws-proxy-yourvpsmaster 2>/dev/null
}

save_ws_config() {
    local PORTS_JSON="$1"
    local SSH_PORT="$2"
    local CUSTOM_RESP="$3"

    mkdir -p "$CONFIG_DIR"
    cat > "${CONFIG_DIR}/ws_proxy.json" << JSONEOF
{
    "ports": ${PORTS_JSON},
    "ssh_host": "127.0.0.1",
    "ssh_port": ${SSH_PORT},
    "response_101": true,
    "custom_response": "${CUSTOM_RESP}",
    "buffer_size": 65536
}
JSONEOF
}

get_active_ports() {
    local CFG="${CONFIG_DIR}/ws_proxy.json"
    if [[ -f "$CFG" ]]; then
        python3 -c "import json; d=json.load(open('$CFG')); print(' '.join(map(str,d.get('ports',[]))))" 2>/dev/null
    else
        echo "80 8080 3128"
    fi
}

show_ws_menu() {
    while true; do
        clear
        show_header
        echo ""
        echo -e "${BMAGENTA}  🍄  PROXY PYTHON3 / WEBSOCKET  🍄${NC}"
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo ""

        local ACTIVE_PORTS
        ACTIVE_PORTS=$(get_active_ports)
        local WS_STATUS="INACTIVO"
        pgrep -f "ws_proxy.py" >/dev/null 2>&1 && WS_STATUS="${GREEN}ACTIVO${NC}"

        echo -e "  ${GREEN}• Estado   :${NC} ${WS_STATUS}"
        echo -e "  ${GREEN}• Puertos  :${NC} ${CYAN}${ACTIVE_PORTS}${NC}"
        echo ""
        echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"
        echo -e "${BYELLOW}  [1]${NC} ➪ Instalar WebSocket Proxy"
        echo -e "${BYELLOW}  [2]${NC} ➪ Agregar puerto WebSocket"
        echo -e "${BYELLOW}  [3]${NC} ➪ Eliminar puerto WebSocket"
        echo -e "${BYELLOW}  [4]${NC} ➪ Iniciar servidor WebSocket"
        echo -e "${BYELLOW}  [5]${NC} ➪ Detener servidor WebSocket"
        echo -e "${BYELLOW}  [6]${NC} ➪ Reiniciar servidor WebSocket"
        echo -e "${BYELLOW}  [7]${NC} ➪ Ver puertos activos"
        echo -e "${BYELLOW}  [8]${NC} ➪ Configurar respuesta HTTP 101 custom"
        echo -e "${BYELLOW}  [9]${NC} ➪ Ver logs"
        echo -e "${BYELLOW}  [10]${NC} ➪ Desinstalar WebSocket Proxy"
        echo ""
        echo -e "  ${BYELLOW}[0]${NC} ➪ ${BRED}[ REGRESAR ]${NC}"
        echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt

        case "$opt" in
            1)  install_ws_proxy ;;
            2)  add_port ;;
            3)  remove_port ;;
            4)  start_ws ;;
            5)  stop_ws ;;
            6)  stop_ws; sleep 1; start_ws ;;
            7)  show_active_ports ;;
            8)  configure_custom_response ;;
            9)  view_ws_logs ;;
            10) uninstall_ws ;;
            0)  return ;;
            *) echo -e "${RED}  Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

install_ws_proxy() {
    clear
    echo -e "${CYAN}  [*] Instalando WebSocket Proxy Python3...${NC}"
    pip3 install -q websockets 2>/dev/null
    mkdir -p "$WS_DIR"
    create_ws_server
    create_ws_service

    # Config por defecto
    save_ws_config '[80, 8080, 3128, 2082]' '22' ''

    # Abrir puertos
    for p in 80 8080 3128 2082; do
        iptables -I INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null
    done

    config_set "PROTO_WS" "1"
    echo -e "${GREEN}  [✓] WebSocket Proxy instalado${NC}"
    echo -e "${CYAN}  Puertos por defecto: 80, 8080, 3128, 2082${NC}"
    press_enter
}

add_port() {
    clear
    echo -e "${CYAN}  Puertos actuales: $(get_active_ports)${NC}"
    echo ""
    echo -ne "${MAGENTA}  ► Nuevo puerto a agregar: ${NC}"
    read -r NEW_PORT

    [[ ! "$NEW_PORT" =~ ^[0-9]+$ ]] || [[ "$NEW_PORT" -lt 1 ]] || [[ "$NEW_PORT" -gt 65535 ]] && {
        echo -e "${RED}  Puerto inválido${NC}"; sleep 2; return
    }

    # Actualizar JSON
    python3 - << PYEOF
import json, sys
cfg_file = "/opt/yourvpsmaster/configs/ws_proxy.json"
try:
    with open(cfg_file) as f:
        cfg = json.load(f)
except:
    cfg = {"ports": [80, 8080, 3128], "ssh_host": "127.0.0.1", "ssh_port": 22}

port = int($NEW_PORT)
if port not in cfg["ports"]:
    cfg["ports"].append(port)
    cfg["ports"].sort()
    with open(cfg_file, "w") as f:
        json.dump(cfg, f, indent=4)
    print(f"Puerto {port} agregado")
else:
    print(f"Puerto {port} ya existe")
PYEOF

    iptables -I INPUT -p tcp --dport "$NEW_PORT" -j ACCEPT 2>/dev/null
    echo -e "${GREEN}  [✓] Puerto ${NEW_PORT} agregado${NC}"
    echo -e "${YELLOW}  Reinicia el proxy para aplicar cambios (opción 6)${NC}"
    press_enter
}

remove_port() {
    clear
    echo -e "${CYAN}  Puertos actuales: $(get_active_ports)${NC}"
    echo ""
    echo -ne "${MAGENTA}  ► Puerto a eliminar: ${NC}"
    read -r DEL_PORT

    python3 - << PYEOF
import json
cfg_file = "/opt/yourvpsmaster/configs/ws_proxy.json"
try:
    with open(cfg_file) as f:
        cfg = json.load(f)
    port = int($DEL_PORT)
    if port in cfg["ports"]:
        cfg["ports"].remove(port)
        with open(cfg_file, "w") as f:
            json.dump(cfg, f, indent=4)
        print(f"Puerto {port} eliminado")
    else:
        print(f"Puerto {port} no encontrado")
except Exception as e:
    print(f"Error: {e}")
PYEOF
    echo -e "${YELLOW}  Reinicia el proxy para aplicar (opción 6)${NC}"
    press_enter
}

start_ws() {
    stop_ws 2>/dev/null
    systemctl start ws-proxy-yourvpsmaster 2>/dev/null || {
        nohup python3 "${WS_DIR}/ws_proxy.py" > "${LOG_DIR}/ws_proxy.log" 2>&1 &
        echo $! > "${PID_DIR}/ws_proxy.pid"
    }
    sleep 1
    local PORTS
    PORTS=$(get_active_ports)
    echo -e "${GREEN}  [✓] WebSocket Proxy iniciado${NC}"
    echo -e "${CYAN}  Puertos activos: ${PORTS}${NC}"

    for p in $PORTS; do
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null
    done
    press_enter
}

stop_ws() {
    systemctl stop ws-proxy-yourvpsmaster 2>/dev/null
    pkill -f "ws_proxy.py" 2>/dev/null
    rm -f "${PID_DIR}/ws_proxy.pid"
    echo -e "${RED}  [✓] WebSocket Proxy detenido${NC}"
}

show_active_ports() {
    clear
    local IP
    IP=$(get_ip)
    echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
    echo -e "${BMAGENTA}  🍄  PUERTOS WEBSOCKET ACTIVOS  🍄${NC}"
    echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
    echo ""
    local PORTS
    PORTS=$(get_active_ports)
    for p in $PORTS; do
        local STATUS
        STATUS=$(port_status "$p")
        echo -e "  ${GREEN}• Puerto ${YELLOW}${p}${NC}: ${STATUS}  →  ws://${IP}:${p}"
    done
    echo ""
    echo -e "${DIM}  Para HTTP Injector: usa cualquiera de estos puertos${NC}"
    echo -e "${DIM}  Respuesta: HTTP/1.1 101 Switching Protocols${NC}"
    press_enter
}

configure_custom_response() {
    clear
    echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
    echo -e "${BMAGENTA}  🍄  RESPUESTA HTTP CUSTOM  🍄${NC}"
    echo -e "${CYAN}  ════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}  Opciones de respuesta:${NC}"
    echo -e "  ${BYELLOW}[1]${NC} HTTP/1.1 101 Switching Protocols  ${GREEN}(recomendado)${NC}"
    echo -e "  ${BYELLOW}[2]${NC} HTTP/1.1 200 Connection Established"
    echo -e "  ${BYELLOW}[3]${NC} HTTP/1.1 200 OK"
    echo -e "  ${BYELLOW}[4]${NC} Respuesta personalizada"
    echo ""
    echo -ne "${MAGENTA}  ► Opcion : ${NC}"
    read -r r

    local CFG="${CONFIG_DIR}/ws_proxy.json"
    case "$r" in
        1) python3 -c "import json; d=json.load(open('$CFG')); d['custom_response']=''; json.dump(d,open('$CFG','w'),indent=4)" 2>/dev/null
           echo -e "${GREEN}  Usando respuesta 101 (por defecto)${NC}" ;;
        2) python3 -c "import json; d=json.load(open('$CFG')); d['custom_response']='HTTP/1.1 200 Connection Established[crlf][crlf]'; json.dump(d,open('$CFG','w'),indent=4)" 2>/dev/null
           echo -e "${GREEN}  Usando 200 Connection Established${NC}" ;;
        3) python3 -c "import json; d=json.load(open('$CFG')); d['custom_response']='HTTP/1.1 200 OK[crlf]Content-Length: 0[crlf][crlf]'; json.dump(d,open('$CFG','w'),indent=4)" 2>/dev/null
           echo -e "${GREEN}  Usando 200 OK${NC}" ;;
        4) echo -ne "${MAGENTA}  ► Respuesta custom (usa [crlf] para salto): ${NC}"
           read -r CUSTOM
           python3 -c "import json; d=json.load(open('$CFG')); d['custom_response']='${CUSTOM}'; json.dump(d,open('$CFG','w'),indent=4)" 2>/dev/null
           echo -e "${GREEN}  Respuesta custom guardada${NC}" ;;
    esac
    echo -e "${YELLOW}  Reinicia el proxy para aplicar (opción 6)${NC}"
    press_enter
}

view_ws_logs() {
    clear
    echo -e "${CYAN}  Últimas 40 líneas de log WebSocket:${NC}"
    echo ""
    [[ -f "${LOG_DIR}/ws_proxy.log" ]] && tail -40 "${LOG_DIR}/ws_proxy.log" || \
        echo -e "${YELLOW}  No hay logs disponibles${NC}"
    press_enter
}

uninstall_ws() {
    confirm "¿Desinstalar WebSocket Proxy?" || return
    stop_ws
    systemctl disable ws-proxy-yourvpsmaster 2>/dev/null
    rm -f /etc/systemd/system/ws-proxy-yourvpsmaster.service
    rm -rf "$WS_DIR"
    config_set "PROTO_WS" "0"
    echo -e "${GREEN}  [✓] WebSocket Proxy desinstalado${NC}"
    press_enter
}

show_ws_menu
