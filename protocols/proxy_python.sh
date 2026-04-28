#!/bin/bash
# ============================================================
#   YOURVPSMASTER - PROXY PYTHON3 WEBSOCKET
#   Modos: Screen / System / WS-EPro / Proxy3
# ============================================================

INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

WS_DIR="${INSTALL_DIR}/protocols/ws_python"
WS_CONF="${CONFIG_DIR}/ws_proxy.json"
WS_PY="${WS_DIR}/ws_proxy.py"
WS_LOG="${LOG_DIR}/ws_proxy.log"

# ─────────────────────────────────────────────────────────────
#   GENERADOR DEL SERVIDOR PYTHON3
# ─────────────────────────────────────────────────────────────
create_ws_server() {
    mkdir -p "$WS_DIR"
    cat > "${WS_PY}" << 'PYEOF'
#!/usr/bin/env python3
"""
YourVPSMaster - WebSocket/HTTP Proxy
Compatible: HTTP Injector, HA Tunnel, KPN Tunnel, HTTP Custom
"""
import asyncio, os, sys, json, logging

CONFIG_FILE = "/opt/yourvpsmaster/configs/ws_proxy.json"
LOG_FILE    = "/opt/yourvpsmaster/logs/ws_proxy.log"
PID_FILE    = "/opt/yourvpsmaster/pids/ws_proxy.pid"

os.makedirs("/opt/yourvpsmaster/logs", exist_ok=True)
os.makedirs("/opt/yourvpsmaster/pids", exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(message)s',
    datefmt='%H:%M:%S',
    handlers=[logging.FileHandler(LOG_FILE), logging.StreamHandler()]
)
log = logging.getLogger("wsproxy")

def load_cfg():
    defaults = {
        "ports":       [80],
        "local_port":  22,
        "local_host":  "127.0.0.1",
        "response":    "101",
        "custom_resp": "",
        "banner":      "yourvpsmaster",
        "buffer":      65536
    }
    try:
        with open(CONFIG_FILE) as f:
            d = json.load(f)
            defaults.update(d)
    except:
        pass
    return defaults

def build_response(cfg):
    custom = cfg.get("custom_resp", "").strip()
    if custom:
        r = custom.replace("\\r\\n", "\r\n").replace("[crlf]", "\r\n").replace("[lfcr]", "\n\r")
        if not r.endswith("\r\n\r\n"):
            r += "\r\n"
        return r.encode()
    code = str(cfg.get("response", "101")).strip()
    if code == "101":
        return b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
    elif code == "200":
        return b"HTTP/1.1 200 Connection Established\r\n\r\n"
    elif code == "403":
        return b"HTTP/1.1 403 Forbidden\r\n\r\n"
    elif code == "500":
        return b"HTTP/1.1 500 Internal Server Error\r\n\r\n"
    else:
        return (f"HTTP/1.1 {code} Connection Established\r\n\r\n").encode()

async def pipe(src_r, dst_w, buf=65536):
    try:
        while True:
            data = await asyncio.wait_for(src_r.read(buf), timeout=600)
            if not data:
                break
            dst_w.write(data)
            await dst_w.drain()
    except:
        pass
    finally:
        try: dst_w.close()
        except: pass

async def handle(reader, writer, cfg):
    peer = writer.get_extra_info('peername', ('?', 0))[0]
    try:
        hdr = b""
        while b"\r\n\r\n" not in hdr:
            chunk = await asyncio.wait_for(reader.read(4096), timeout=15)
            if not chunk:
                break
            hdr += chunk
            if len(hdr) > 16384:
                break
        first = hdr.decode(errors='ignore').split('\r\n')[0]
        log.info(f"[{peer}] {first[:80]}")
        try:
            tr, tw = await asyncio.wait_for(
                asyncio.open_connection(cfg["local_host"], cfg["local_port"]),
                timeout=10
            )
        except Exception as e:
            log.warning(f"[{peer}] No se pudo conectar a {cfg['local_host']}:{cfg['local_port']}: {e}")
            writer.close()
            return
        writer.write(build_response(cfg))
        await writer.drain()
        parts = hdr.split(b"\r\n\r\n", 1)
        if len(parts) > 1 and parts[1]:
            tw.write(parts[1])
            await tw.drain()
        await asyncio.gather(
            pipe(reader, tw, cfg["buffer"]),
            pipe(tr, writer, cfg["buffer"]),
            return_exceptions=True
        )
    except Exception as e:
        log.error(f"[{peer}] {e}")
    finally:
        try: writer.close()
        except: pass

async def main():
    cfg   = load_cfg()
    ports = cfg.get("ports", [80])
    log.info("=" * 50)
    log.info(f"  YourVPSMaster WebSocket Proxy")
    log.info(f"  Puertos  : {ports}")
    log.info(f"  Destino  : {cfg['local_host']}:{cfg['local_port']}")
    log.info(f"  Respuesta: HTTP {cfg.get('response','101')}")
    log.info("=" * 50)
    servers = []
    for port in ports:
        try:
            srv = await asyncio.start_server(
                lambda r, w, c=cfg: handle(r, w, c),
                "0.0.0.0", port,
                reuse_address=True, reuse_port=True
            )
            servers.append(srv)
            log.info(f"  [OK] Puerto {port} activo")
        except Exception as e:
            log.error(f"  [!!] Puerto {port}: {e}")
    if not servers:
        log.error("Ningún puerto pudo iniciarse")
        sys.exit(1)
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except: pass
    # Mantener todos los servidores corriendo
    async with asyncio.TaskGroup() as tg:
        for srv in servers:
            tg.create_task(srv.serve_forever())

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Detenido")
PYEOF
    chmod +x "${WS_PY}"
}

# ─────────────────────────────────────────────────────────────
#   GUARDAR CONFIG JSON
# ─────────────────────────────────────────────────────────────
save_cfg() {
    local PORTS_JSON="$1"
    local LOCAL_PORT="$2"
    local RESPONSE="$3"
    local CUSTOM="$4"
    local BANNER="$5"
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$PID_DIR"
    cat > "${WS_CONF}" << JSONEOF
{
    "ports":       ${PORTS_JSON},
    "local_port":  ${LOCAL_PORT},
    "local_host":  "127.0.0.1",
    "response":    "${RESPONSE}",
    "custom_resp": "${CUSTOM}",
    "banner":      "${BANNER}",
    "buffer":      65536
}
JSONEOF
}

cfg_val() {
    local KEY="$1"
    python3 -c "
import json, sys
try:
    d = json.load(open('${WS_CONF}'))
    v = d.get('${KEY}','')
    if isinstance(v, list): print(' '.join(map(str,v)))
    else: print(v)
except: pass
" 2>/dev/null
}

ports_array() {
    python3 -c "
import json
try:
    d = json.load(open('${WS_CONF}'))
    print(json.dumps(d.get('ports',[80])))
except: print('[80]')
" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────
#   SEPARADORES VISUALES
# ─────────────────────────────────────────────────────────────
sep()  { echo -e "${YELLOW}  ────────────────────────────────────────────────────${NC}"; }
sep2() { echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"; }

# ─────────────────────────────────────────────────────────────
#   WIZARD INTERACTIVO — replica la captura de pantalla
# ─────────────────────────────────────────────────────────────
wizard_setup() {
    clear
    echo ""
    echo -e "${BMAGENTA}  🍄  INSTALACION DE PROTOCOLOS  🍄${NC}"
    sep2
    echo ""

    # ── Puerto Principal ──────────────────────────────────────
    sep
    echo -e "${WHITE}          Puerto Principal, para Proxy WS/Directo${NC}"
    sep
    echo ""
    local CUR_PORTS
    CUR_PORTS=$(cfg_val "ports" 2>/dev/null)
    [[ -n "$CUR_PORTS" ]] && \
        echo -e "${GREEN}  Puerto python: ${YELLOW}${CUR_PORTS} ${GREEN}VALIDO${NC}" || \
        echo -e "${GREEN}  Puerto python: ${YELLOW}80 ${GREEN}(por defecto)${NC}"
    echo ""
    echo -ne "${MAGENTA}  -> : ${NC}"
    read -r WS_PORT
    WS_PORT="${WS_PORT:-80}"
    echo ""
    echo -e "${GREEN}  Puerto python: ${YELLOW}${WS_PORT} ${GREEN}VALIDO${NC}"
    echo ""

    # ── Puerto Local SSH / DROPBEAR / OPENVPN ─────────────────
    sep
    echo -e "${WHITE}          Puerto Local SSH/DROPBEAR/OPENVPN${NC}"
    sep
    echo ""
    local CUR_LOCAL
    CUR_LOCAL=$(cfg_val "local_port" 2>/dev/null)
    [[ -n "$CUR_LOCAL" ]] && \
        echo -e "${GREEN}  Puerto local: ${YELLOW}${CUR_LOCAL} ${GREEN}VALIDO${NC}" || \
        echo -e "${GREEN}  Puerto local: ${YELLOW}22 ${GREEN}(por defecto)${NC}"
    echo ""
    echo -ne "${MAGENTA}  -> : ${NC}"
    read -r LOCAL_PORT
    LOCAL_PORT="${LOCAL_PORT:-22}"
    echo ""
    echo -e "${GREEN}  Puerto local: ${YELLOW}${LOCAL_PORT} ${GREEN}VALIDO${NC}"
    echo ""

    # ── Código de Respuesta ────────────────────────────────────
    sep
    echo -e "${GREEN}  RESPONDE DE CABECERA ${YELLOW}(101,200,403,500,etc)${NC}"
    sep
    echo ""
    echo -e "${WHITE}          Response personalizado (enter por defecto 200)${NC}"
    echo -e "${WHITE}          NOTA : Para OVER WEBSOCKET escribe ${CYAN}[ 101 ]${NC}"
    echo ""
    local CUR_RESP
    CUR_RESP=$(cfg_val "response" 2>/dev/null)
    [[ -n "$CUR_RESP" ]] && \
        echo -e "${GREEN}  RESPONSE : ${YELLOW}${CUR_RESP} ${GREEN}VALIDA${NC}" || \
        echo -e "${GREEN}  RESPONSE : ${YELLOW}200 ${GREEN}(por defecto)${NC}"
    echo ""
    echo -ne "${MAGENTA}  -> : ${NC}"
    read -r RESPONSE
    RESPONSE="${RESPONSE:-200}"
    echo ""
    echo -e "${GREEN}  RESPONSE : ${YELLOW}${RESPONSE} ${GREEN}VALIDA${NC}"
    echo ""

    # ── Encabezado Personalizado ───────────────────────────────
    sep
    echo -e "${WHITE}               ENCABEZADO PERSONALIZADO${NC}"
    sep
    echo ""
    echo -e "${WHITE}                    * EJEMPLO *${NC}"
    sep
    echo ""
    echo -e "${CYAN}  \\r\\nContent-length: 0\\r\\n\\r\\nHTTP/1.1 200 Connection Established\\${NC}"
    echo -e "${CYAN}  r\\n\\r\\n${NC}"
    echo ""
    sep
    echo -e "${WHITE}              SI DESCONOCES DE ESTA OPCION${NC}"
    echo -e "${WHITE}                  SOLO PRESIONA ENTER${NC}"
    sep
    echo ""
    local CUR_CUSTOM
    CUR_CUSTOM=$(cfg_val "custom_resp" 2>/dev/null)
    [[ -n "$CUR_CUSTOM" ]] && \
        echo -e "${GREEN}  CABECERA : ${YELLOW}${CUR_CUSTOM}${NC}" || \
        echo -e "${GREEN}  CABECERA : ${YELLOW}DEFAULT_HOST${NC}"
    echo ""
    echo -ne "${MAGENTA}  -> : ${NC}"
    read -r CUSTOM_RESP
    echo ""

    # ── Mini-Banner ────────────────────────────────────────────
    sep
    echo -e "${WHITE}                Introdusca su Mini-Banner${NC}"
    sep
    echo ""
    echo -e "${WHITE}          Introduzca un texto [NORMAL] o en [HTML]${NC}"
    local CUR_BANNER
    CUR_BANNER=$(cfg_val "banner" 2>/dev/null)
    [[ -n "$CUR_BANNER" ]] && \
        echo -e "${GREEN}  -> : ${CYAN}${CUR_BANNER}${NC}" || \
        echo -e "${GREEN}  -> : ${CYAN}yourvpsmaster${NC}"
    echo -ne "${MAGENTA}  -> : ${NC}"
    read -r BANNER
    BANNER="${BANNER:-yourvpsmaster}"
    echo ""

    # Construir JSON de puertos
    local PORTS_JSON
    PORTS_JSON=$(python3 -c "
import json, sys
raw = '${WS_PORT}'
parts = [int(x.strip()) for x in raw.replace(',',' ').split() if x.strip().isdigit()]
if not parts: parts = [80]
print(json.dumps(parts))
" 2>/dev/null || echo "[80]")

    save_cfg "$PORTS_JSON" "$LOCAL_PORT" "$RESPONSE" "$CUSTOM_RESP" "$BANNER"
    create_ws_server
    ensure_service

    for p in $(echo "$WS_PORT" | tr ',' ' '); do
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null
    done
    iptables -I INPUT -p tcp --dport "$LOCAL_PORT" -j ACCEPT 2>/dev/null

    config_set "PROTO_WS" "1"

    echo -e "${GREEN}  [✓] Configuración guardada${NC}"
    echo ""
    press_enter

    launch_menu
}

# ─────────────────────────────────────────────────────────────
#   MENÚ DE LANZAMIENTO — replica las 4 opciones de la captura
# ─────────────────────────────────────────────────────────────
launch_menu() {
    while true; do
        clear
        echo ""
        echo -e "${BMAGENTA}  🍄  INSTALACION DE PROTOCOLOS  🍄${NC}"
        sep2

        local CNT_SCR CNT_SYS CNT_EPR CNT_P3
        CNT_SCR=$(screen -ls 2>/dev/null | grep -c "ws_screen"  || echo 0)
        CNT_SYS=$(systemctl is-active ws-proxy-yourvpsmaster 2>/dev/null | grep -c "^active$" || echo 0)
        CNT_EPR=$(pgrep -fc "ws_epro"   2>/dev/null || echo 0)
        CNT_P3=$(pgrep -fc "ws_proxy3" 2>/dev/null || echo 0)

        local PORTS LOCAL RESP BANNER
        PORTS=$(cfg_val "ports");  PORTS="${PORTS:-80}"
        LOCAL=$(cfg_val "local_port"); LOCAL="${LOCAL:-22}"
        RESP=$(cfg_val "response");   RESP="${RESP:-101}"
        BANNER=$(cfg_val "banner");   BANNER="${BANNER:-yourvpsmaster}"

        echo ""
        echo -e "  ${GREEN}Puerto WS  :${NC} ${YELLOW}${PORTS}${NC}   ${GREEN}Local SSH:${NC} ${YELLOW}${LOCAL}${NC}   ${GREEN}Resp:${NC} ${CYAN}${RESP}${NC}"
        echo -e "  ${GREEN}Banner     :${NC} ${CYAN}${BANNER}${NC}"
        echo ""
        sep
        echo ""
        echo -e "${CYAN}  [1]${NC} > Proxy (WS/Direct) (SCREEN)   ${YELLOW}${CNT_SCR}${NC}"
        echo -e "${CYAN}  [2]${NC} > Proxy (WS/Direct) (SYSTEM)   ${YELLOW}[REF]${NC}"
        echo -e "${CYAN}  [3]${NC} > Proxy (WS-EPro)  ( System )  ${YELLOW}${CNT_EPR}${NC}"
        echo -e "${CYAN}  [4]${NC} > [!] Proxy3 (WS) ( SCREEN )   ${YELLOW}${CNT_P3}${NC}"
        echo ""
        sep
        echo -e "${BYELLOW}  [5]${NC} ➪ Reconfigurar (wizard)"
        echo -e "${BYELLOW}  [6]${NC} ➪ Agregar puerto adicional"
        echo -e "${BYELLOW}  [7]${NC} ➪ Ver puertos activos"
        echo -e "${BYELLOW}  [8]${NC} ➪ Ver logs"
        echo -e "${BRED}  [9]${NC} ➪ Detener todos los proxies"
        echo ""
        echo -e "  ${CYAN}[0]${NC} >  $(echo -e "${BRED}VOLVER${NC}")"
        sep2
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt

        case "$opt" in
            1) start_screen_proxy ;;
            2) start_system_proxy ;;
            3) start_epro_proxy ;;
            4) start_proxy3 ;;
            5) wizard_setup; return ;;
            6) add_extra_port ;;
            7) show_active_ports ;;
            8) view_logs ;;
            9) stop_all ;;
            0) return ;;
            *) echo -e "${RED}  Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────
#   [1] SCREEN
# ─────────────────────────────────────────────────────────────
start_screen_proxy() {
    ensure_deps
    stop_screen_proxy 2>/dev/null
    echo -e "${CYAN}  [*] Iniciando Proxy WS/Direct en SCREEN...${NC}"

    # Matar instancias previas para liberar puertos
    pkill -f "ws_proxy.py" 2>/dev/null; sleep 1

    screen -dmS ws_screen bash -c "python3 ${WS_PY} >> ${WS_LOG} 2>&1"
    sleep 2

    if screen -ls 2>/dev/null | grep -q "ws_screen"; then
        echo -e "${GREEN}  [✓] Corriendo en screen 'ws_screen'${NC}"
        echo -e "${DIM}  Acceder: screen -r ws_screen${NC}"
    else
        nohup python3 "${WS_PY}" >> "${WS_LOG}" 2>&1 &
        echo $! > "${PID_DIR}/ws_proxy.pid"
        echo -e "${GREEN}  [✓] Proxy en background (PID: $!)${NC}"
    fi
    open_fw_ports
    echo -e "${CYAN}  Puertos: ${YELLOW}$(cfg_val ports)${NC}"
    press_enter
}

stop_screen_proxy() { screen -S ws_screen -X quit 2>/dev/null; }

# ─────────────────────────────────────────────────────────────
#   [2] SYSTEM (systemd)
# ─────────────────────────────────────────────────────────────
start_system_proxy() {
    ensure_deps
    ensure_service
    pkill -f "ws_proxy.py" 2>/dev/null; sleep 1

    echo -e "${CYAN}  [*] Iniciando Proxy WS/Direct como servicio SYSTEM...${NC}"
    systemctl restart ws-proxy-yourvpsmaster 2>/dev/null
    sleep 2

    if systemctl is-active --quiet ws-proxy-yourvpsmaster 2>/dev/null; then
        echo -e "${GREEN}  [✓] Servicio SYSTEM activo${NC}"
        echo -e "${DIM}  Estado: systemctl status ws-proxy-yourvpsmaster${NC}"
    else
        # Fallback nohup
        nohup python3 "${WS_PY}" >> "${WS_LOG}" 2>&1 &
        echo $! > "${PID_DIR}/ws_proxy.pid"
        echo -e "${GREEN}  [✓] Proxy en background (PID: $!)${NC}"
    fi
    echo -e "${CYAN}  Puertos: ${YELLOW}$(cfg_val ports)${NC}"
    open_fw_ports
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   [3] WS-EPro (respuesta forzada 101)
# ─────────────────────────────────────────────────────────────
start_epro_proxy() {
    ensure_deps
    pkill -f "ws_epro.py" 2>/dev/null
    local PORTS_ARR LOCAL
    PORTS_ARR=$(ports_array)
    LOCAL=$(cfg_val "local_port"); LOCAL="${LOCAL:-22}"

    echo -e "${CYAN}  [*] Iniciando Proxy WS-EPro (respuesta 101 forzada)...${NC}"

    # Crear variante epro con respuesta siempre 101
    cat > "${WS_DIR}/ws_epro.py" << PYEPRO
#!/usr/bin/env python3
import asyncio, os, sys, json, logging
LOG = "/opt/yourvpsmaster/logs/ws_proxy.log"
logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(message)s',
    datefmt='%H:%M:%S', handlers=[logging.FileHandler(LOG), logging.StreamHandler()])
log = logging.getLogger("epro")
PORTS = ${PORTS_ARR}
LOCAL = ${LOCAL}

async def pipe(r, w):
    try:
        while True:
            d = await asyncio.wait_for(r.read(65536), timeout=600)
            if not d: break
            w.write(d); await w.drain()
    except: pass
    finally:
        try: w.close()
        except: pass

async def handle(reader, writer):
    peer = writer.get_extra_info('peername',('?',0))[0]
    hdr = b""
    try:
        while b"\r\n\r\n" not in hdr:
            c = await asyncio.wait_for(reader.read(4096), timeout=10)
            if not c: break
            hdr += c
        tr, tw = await asyncio.open_connection("127.0.0.1", LOCAL)
        writer.write(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        await writer.drain()
        pts = hdr.split(b"\r\n\r\n", 1)
        if len(pts) > 1 and pts[1]:
            tw.write(pts[1]); await tw.drain()
        await asyncio.gather(pipe(reader,tw), pipe(tr,writer), return_exceptions=True)
    except Exception as e:
        log.error(f"[{peer}] {e}")
    finally:
        try: writer.close()
        except: pass

async def main():
    servers = []
    for p in PORTS:
        try:
            s = await asyncio.start_server(handle,"0.0.0.0",p,reuse_address=True,reuse_port=True)
            servers.append(s); log.info(f"WS-EPro puerto {p}")
        except Exception as e:
            log.error(f"Puerto {p} error: {e}")
    if not servers: sys.exit(1)
    with open("/opt/yourvpsmaster/pids/ws_epro.pid","w") as f:
        f.write(str(os.getpid()))
    async with asyncio.TaskGroup() as tg:
        for s in servers: tg.create_task(s.serve_forever())

asyncio.run(main())
PYEPRO
    chmod +x "${WS_DIR}/ws_epro.py"

    nohup python3 "${WS_DIR}/ws_epro.py" >> "${WS_LOG}" 2>&1 &
    echo $! > "${PID_DIR}/ws_epro.pid"
    sleep 1
    echo -e "${GREEN}  [✓] WS-EPro iniciado (respuesta 101)${NC}"
    echo -e "${CYAN}  Puertos: ${YELLOW}$(cfg_val ports)${NC}"
    open_fw_ports
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   [4] Proxy3 WS — SCREEN (instancia independiente)
# ─────────────────────────────────────────────────────────────
start_proxy3() {
    ensure_deps
    screen -S ws_proxy3 -X quit 2>/dev/null
    echo -e "${CYAN}  [*] Iniciando Proxy3 (WS) en SCREEN...${NC}"
    screen -dmS ws_proxy3 bash -c "python3 ${WS_PY} >> ${WS_LOG} 2>&1"
    sleep 2
    if screen -ls 2>/dev/null | grep -q "ws_proxy3"; then
        echo -e "${GREEN}  [✓] Proxy3 en screen 'ws_proxy3'${NC}"
    else
        nohup python3 "${WS_PY}" >> "${WS_LOG}" 2>&1 &
        echo $! > "${PID_DIR}/ws_proxy3.pid"
        echo -e "${GREEN}  [✓] Proxy3 en background (PID: $!)${NC}"
    fi
    echo -e "${CYAN}  Puertos: ${YELLOW}$(cfg_val ports)${NC}"
    open_fw_ports
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   DETENER TODO
# ─────────────────────────────────────────────────────────────
stop_all() {
    echo -e "${RED}  [*] Deteniendo todos los proxies...${NC}"
    systemctl stop ws-proxy-yourvpsmaster 2>/dev/null
    screen -S ws_screen  -X quit 2>/dev/null
    screen -S ws_proxy3  -X quit 2>/dev/null
    pkill -f "ws_proxy.py"  2>/dev/null
    pkill -f "ws_epro.py"   2>/dev/null
    rm -f "${PID_DIR}/ws_proxy.pid" "${PID_DIR}/ws_epro.pid" "${PID_DIR}/ws_proxy3.pid"
    config_set "PROTO_WS" "0"
    echo -e "${RED}  [✓] Todos detenidos${NC}"
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   AGREGAR PUERTO EXTRA
# ─────────────────────────────────────────────────────────────
add_extra_port() {
    echo -ne "${MAGENTA}  ► Puerto adicional: ${NC}"
    read -r NP
    [[ ! "$NP" =~ ^[0-9]+$ ]] && { echo -e "${RED}  Inválido${NC}"; sleep 2; return; }
    python3 - << PYEOF
import json
f = "${WS_CONF}"
try:
    with open(f) as fp: d = json.load(fp)
except:
    d = {"ports":[80],"local_port":22,"response":"101","custom_resp":"","banner":"yourvpsmaster","buffer":65536}
p = int(${NP})
if p not in d["ports"]:
    d["ports"].append(p); d["ports"].sort()
    with open(f,"w") as fp: json.dump(d, fp, indent=4)
    print(f"  Puerto {p} agregado")
else:
    print(f"  Puerto {p} ya existía")
PYEOF
    iptables -I INPUT -p tcp --dport "$NP" -j ACCEPT 2>/dev/null
    echo -e "${YELLOW}  Reinicia el proxy para aplicar${NC}"
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   VER PUERTOS
# ─────────────────────────────────────────────────────────────
show_active_ports() {
    clear
    local IP
    IP=$(get_ip)
    echo -e "${BMAGENTA}  🍄 PUERTOS WEBSOCKET  🍄${NC}"
    sep2
    echo ""
    for p in $(cfg_val "ports"); do
        echo -e "  ${GREEN}• Puerto ${YELLOW}${p}${NC}: $(port_status $p)   →   ${CYAN}ws://${IP}:${p}${NC}"
    done
    echo ""
    echo -e "  ${GREEN}Respuesta : ${CYAN}HTTP $(cfg_val response)${NC}"
    echo -e "  ${GREEN}SSH local : ${CYAN}$(cfg_val local_port)${NC}"
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   LOGS
# ─────────────────────────────────────────────────────────────
view_logs() {
    clear
    echo -e "${CYAN}  ws_proxy.log — últimas 40 líneas:${NC}"
    echo ""
    [[ -f "${WS_LOG}" ]] && tail -40 "${WS_LOG}" || echo -e "${YELLOW}  Sin logs${NC}"
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   HELPERS
# ─────────────────────────────────────────────────────────────
ensure_deps() {
    command -v python3 &>/dev/null || apt-get install -y -qq python3 2>/dev/null
    command -v screen  &>/dev/null || apt-get install -y -qq screen  2>/dev/null
    mkdir -p "$WS_DIR" "$CONFIG_DIR" "$LOG_DIR" "$PID_DIR"
    [[ ! -f "$WS_PY"   ]] && create_ws_server
    [[ ! -f "$WS_CONF" ]] && save_cfg "[80]" "22" "101" "" "yourvpsmaster"
}

ensure_service() {
    if [[ ! -f /etc/systemd/system/ws-proxy-yourvpsmaster.service ]]; then
        cat > /etc/systemd/system/ws-proxy-yourvpsmaster.service << SVCEOF
[Unit]
Description=YourVPSMaster WebSocket Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${WS_PY}
Restart=always
RestartSec=3
StandardOutput=append:${WS_LOG}
StandardError=append:${WS_LOG}

[Install]
WantedBy=multi-user.target
SVCEOF
        systemctl daemon-reload
        systemctl enable ws-proxy-yourvpsmaster 2>/dev/null
    fi
}

open_fw_ports() {
    for p in $(cfg_val "ports"); do
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null
    done
}

# ─────────────────────────────────────────────────────────────
#   ENTRADA PRINCIPAL
# ─────────────────────────────────────────────────────────────
if [[ -f "$WS_CONF" ]]; then
    launch_menu
else
    wizard_setup
fi
