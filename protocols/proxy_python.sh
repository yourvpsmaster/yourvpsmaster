#!/bin/bash
# ============================================================
#   YOURVPSMASTER - PROXY PYTHON3 WEBSOCKET
#   6 Modos: SIMPLE / SEGURO / DIRETO(WS) / OPENVPN /
#            GETTUNEL / TCP BYPASS
#
#   FIX CRÍTICO: La respuesta HTTP se envía ANTES de conectar
#   a SSH — esto es lo que necesita HTTP Injector para funcionar
# ============================================================

INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

WS_DIR="${INSTALL_DIR}/protocols/ws_python"
WS_CONF="${CONFIG_DIR}/ws_proxy.json"
WS_LOG="${LOG_DIR}/ws_proxy.log"

mkdir -p "$WS_DIR" "$CONFIG_DIR" "$LOG_DIR" "$PID_DIR"

# ─────────────────────────────────────────────────────────────
#   SEPARADORES VISUALES
# ─────────────────────────────────────────────────────────────
sep()  { echo -e "${YELLOW}  ────────────────────────────────────────────────────${NC}"; }
sep2() { echo -e "${YELLOW}  ════════════════════════════════════════════════════${NC}"; }

# ─────────────────────────────────────────────────────────────
#   CONFIG JSON helpers
# ─────────────────────────────────────────────────────────────
cfg_get() {
    python3 -c "
import json, sys
try:
    d = json.load(open('${WS_CONF}'))
    v = d.get('$1', '')
    print(' '.join(map(str, v)) if isinstance(v, list) else str(v))
except:
    pass
" 2>/dev/null
}

cfg_ports_json() {
    python3 -c "
import json
try:
    print(json.dumps(json.load(open('${WS_CONF}')).get('ports', [80])))
except:
    print('[80]')
" 2>/dev/null
}

cfg_save() {
    local PORTS="$1" LOCAL="$2" RESP="$3" CUSTOM="$4" BANNER="$5"
    cat > "${WS_CONF}" << JEOF
{
    "ports":       ${PORTS},
    "local_port":  ${LOCAL},
    "local_host":  "127.0.0.1",
    "response":    "${RESP}",
    "custom_resp": "${CUSTOM}",
    "banner":      "${BANNER}",
    "buffer":      65536
}
JEOF
}

# ─────────────────────────────────────────────────────────────
#   ESTADO [ WORKING ] / [ STOPPED ]
# ─────────────────────────────────────────────────────────────
port_working() {
    local P="$1"
    if ss -tlnp 2>/dev/null | grep -qE ":${P}[ \t]" || \
       lsof -i "TCP:${P}" -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${GREEN}[ WORKING ]${NC}"
    else
        echo -e "${RED}[ STOPPED ]${NC}"
    fi
}

mode_status() {
    local PF="${PID_DIR}/ws_${1}.pid"
    if [[ -f "$PF" ]]; then
        local PID; PID=$(cat "$PF" 2>/dev/null)
        kill -0 "$PID" 2>/dev/null && echo -e "${GREEN}[ON]${NC}" && return
    fi
    echo -e "${RED}[OFF]${NC}"
}

# ─────────────────────────────────────────────────────────────
#   GENERADOR DE SERVIDORES PYTHON3
#
#   PARÁMETROS:
#     $1 OUTFILE     — ruta del .py
#     $2 PIDNAME     — identificador del PID (simple/seguro/etc)
#     $3 LABEL       — etiqueta para logs
#     $4 FORCE_RESP  — "" = usar config | "101" = forzar | "BYPASS" = TCP crudo
#     $5 DEST_PORT   — "" = usar local_port de config | número = puerto fijo
#
#   FIX CRÍTICO aplicado aquí:
#     → writer.write(response) ANTES de open_connection(SSH)
#     → HTTP Injector recibe el 101/200 inmediatamente
#     → luego el túnel SSH se establece en segundo plano
# ─────────────────────────────────────────────────────────────
write_py_server() {
    local OUTFILE="$1" PIDNAME="$2" LABEL="$3" FORCE_RESP="$4" DEST_PORT="$5"
    cat > "${OUTFILE}" << PYEOF
#!/usr/bin/env python3
# YourVPSMaster - Socks Python ${LABEL}
# FIX: respuesta HTTP enviada ANTES de conectar a SSH
import asyncio, os, sys, json, logging

CFG = "/opt/yourvpsmaster/configs/ws_proxy.json"
LOG = "/opt/yourvpsmaster/logs/ws_proxy.log"
PID = "/opt/yourvpsmaster/pids/ws_${PIDNAME}.pid"

os.makedirs(os.path.dirname(LOG), exist_ok=True)
os.makedirs(os.path.dirname(PID), exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s][${LABEL}] %(message)s',
    datefmt='%H:%M:%S',
    handlers=[
        logging.FileHandler(LOG, 'a'),
        logging.StreamHandler(sys.stdout)
    ]
)
log = logging.getLogger()

FORCE_RESP = "${FORCE_RESP}"
FORCE_PORT = "${DEST_PORT}"

def load_cfg():
    d = {"ports": [80], "local_port": 22, "local_host": "127.0.0.1",
         "response": "101", "custom_resp": "", "buffer": 65536}
    try:
        with open(CFG) as f:
            d.update(json.load(f))
    except Exception as e:
        log.warning(f"Config no encontrada, usando defaults: {e}")
    if FORCE_PORT.isdigit():
        d["local_port"] = int(FORCE_PORT)
    return d

def make_response(cfg):
    if FORCE_RESP == "101":
        return b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
    custom = cfg.get("custom_resp", "").strip()
    if custom:
        r = custom.replace("\\\\r\\\\n", "\r\n").replace("[crlf]", "\r\n")
        return (r if r.endswith("\r\n") else r + "\r\n").encode()
    code = str(cfg.get("response", "101")).strip()
    table = {
        "101": b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n",
        "200": b"HTTP/1.1 200 Connection Established\r\n\r\n",
        "403": b"HTTP/1.1 403 Forbidden\r\n\r\n",
        "500": b"HTTP/1.1 500 Internal Server Error\r\n\r\n",
    }
    return table.get(code, f"HTTP/1.1 {code} Connection Established\r\n\r\n".encode())

async def pipe(reader, writer, buf=65536):
    try:
        while True:
            data = await asyncio.wait_for(reader.read(buf), timeout=600)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except:
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except:
            pass

async def handle_client(reader, writer, cfg):
    addr = writer.get_extra_info('peername', ('?', 0))[0]
    buf  = cfg.get("buffer", 65536)

    # ── MODO TCP BYPASS: sin parsear HTTP, pipe directo ────
    if FORCE_RESP == "BYPASS":
        log.info(f"{addr} TCP-BYPASS → :{cfg['local_port']}")
        try:
            tr, tw = await asyncio.wait_for(
                asyncio.open_connection(cfg["local_host"], cfg["local_port"]), 10)
            await asyncio.gather(
                pipe(reader, tw, buf),
                pipe(tr, writer, buf),
                return_exceptions=True)
        except Exception as e:
            log.warning(f"{addr} BYPASS error: {e}")
        finally:
            try: writer.close()
            except: pass
        return

    # ── MODOS HTTP: leer cabecera del cliente ──────────────
    hdr = b""
    try:
        while b"\r\n\r\n" not in hdr:
            chunk = await asyncio.wait_for(reader.read(4096), timeout=15)
            if not chunk:
                writer.close()
                return
            hdr += chunk
            if len(hdr) > 65536:
                break
    except asyncio.TimeoutError:
        log.warning(f"{addr} Timeout leyendo cabecera")
        try: writer.close()
        except: pass
        return

    first_line = hdr.decode(errors='ignore').split('\r\n')[0]
    log.info(f"{addr} {first_line[:80]}")

    # ── FIX CRÍTICO: enviar respuesta HTTP PRIMERO ─────────
    # HTTP Injector / HA Tunnel necesita recibir el 101/200
    # antes de que se establezca el túnel SSH.
    # Si primero conectamos SSH y luego respondemos → FALLA.
    try:
        writer.write(make_response(cfg))
        await writer.drain()
    except Exception as e:
        log.warning(f"{addr} Error enviando respuesta: {e}")
        try: writer.close()
        except: pass
        return

    # ── Ahora conectar al destino SSH/Dropbear ─────────────
    try:
        tr, tw = await asyncio.wait_for(
            asyncio.open_connection(cfg["local_host"], cfg["local_port"]), 10)
    except Exception as e:
        log.warning(f"{addr} Destino :{cfg['local_port']} inaccesible: {e}")
        # El 101 ya fue enviado — cerrar conexión limpiamente
        try: writer.close()
        except: pass
        return

    # Reenviar payload extra que vino junto con la cabecera HTTP
    rest = hdr.split(b"\r\n\r\n", 1)
    if len(rest) > 1 and rest[1]:
        try:
            tw.write(rest[1])
            await tw.drain()
        except:
            pass

    # ── Pipe bidireccional cliente ↔ SSH ───────────────────
    await asyncio.gather(
        pipe(reader, tw, buf),
        pipe(tr, writer, buf),
        return_exceptions=True
    )

async def serve_forever_on(srv):
    async with srv:
        await srv.serve_forever()

async def main():
    cfg   = load_cfg()
    ports = cfg.get("ports", [80])

    log.info("=" * 50)
    log.info(f"  YourVPSMaster - Socks Python ${LABEL}")
    log.info(f"  Puertos  : {ports}")
    if FORCE_RESP != "BYPASS":
        resp = FORCE_RESP if FORCE_RESP else cfg.get('response', '101')
        log.info(f"  Respuesta: HTTP {resp}  (enviada PRIMERO)")
    log.info(f"  SSH dest : {cfg['local_host']}:{cfg['local_port']}")
    log.info("=" * 50)

    servers = []
    for port in ports:
        try:
            srv = await asyncio.start_server(
                lambda r, w, c=cfg: handle_client(r, w, c),
                "0.0.0.0", port,
                reuse_address=True,
                reuse_port=True
            )
            servers.append(srv)
            log.info(f"  [OK] Puerto {port} escuchando")
        except OSError as e:
            log.error(f"  [!!] Puerto {port} no disponible: {e}")
            log.error(f"       Verifica con: ss -tlnp | grep {port}")

    if not servers:
        log.error("No se pudo abrir ningún puerto.")
        log.error("Verifica que no estén ocupados: ss -tlnp")
        sys.exit(1)

    # Guardar PID
    try:
        with open(PID, "w") as f:
            f.write(str(os.getpid()))
    except:
        pass

    # asyncio.gather — compatible Python 3.7+
    await asyncio.gather(
        *[serve_forever_on(s) for s in servers],
        return_exceptions=True
    )

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Detenido")
    except Exception as e:
        log.error(f"Error fatal: {e}")
        sys.exit(1)
PYEOF
    chmod +x "${OUTFILE}"
}

# ─────────────────────────────────────────────────────────────
#   INSTALAR LOS 6 SERVIDORES PYTHON
# ─────────────────────────────────────────────────────────────
install_all_py() {
    echo -e "${CYAN}  [*] Generando servidores Python3 (6 modos)...${NC}"
    #              OUTFILE                         PIDNAME    LABEL         FORCE_RESP  DEST_PORT
    write_py_server "${WS_DIR}/simple.py"    "simple"    "SIMPLE"      ""        ""
    write_py_server "${WS_DIR}/seguro.py"    "seguro"    "SEGURO"      ""        ""
    write_py_server "${WS_DIR}/direto.py"    "direto"    "DIRETO-WS"   "101"     ""
    write_py_server "${WS_DIR}/ovpn.py"      "ovpn"      "OPENVPN"     ""        "1194"
    write_py_server "${WS_DIR}/gettunel.py"  "gettunel"  "GETTUNEL"    "101"     ""
    write_py_server "${WS_DIR}/tcpbypass.py" "tcpbypass" "TCP-BYPASS"  "BYPASS"  ""
    echo -e "${GREEN}  [✓] 6 modos Python3 generados${NC}"
}

# ─────────────────────────────────────────────────────────────
#   LANZAR UN MODO
#   Mata instancias previas en esos puertos, luego inicia
# ─────────────────────────────────────────────────────────────
launch_mode() {
    local NAME="$1" SCRIPT="$2" PIDNAME="$3"
    local PIDFILE="${PID_DIR}/ws_${PIDNAME}.pid"

    echo -e "${CYAN}  [*] Iniciando ${NAME}...${NC}"

    # Matar instancia previa de ESTE modo
    if [[ -f "$PIDFILE" ]]; then
        local OLDPID; OLDPID=$(cat "$PIDFILE" 2>/dev/null)
        if [[ -n "$OLDPID" ]] && kill -0 "$OLDPID" 2>/dev/null; then
            kill "$OLDPID" 2>/dev/null
            sleep 1
        fi
        rm -f "$PIDFILE"
    fi

    # Matar otros procesos Python del WS_DIR en los mismos puertos
    local PORTS; PORTS=$(cfg_get "ports")
    for p in $PORTS; do
        # Obtener PID usando el puerto (sin fuser)
        local PIDS_ON_PORT
        PIDS_ON_PORT=$(ss -tlnp 2>/dev/null | grep ":${p} " | \
            grep -oP 'pid=\K[0-9]+' | sort -u)
        for pid in $PIDS_ON_PORT; do
            if kill -0 "$pid" 2>/dev/null; then
                local CMD; CMD=$(cat "/proc/${pid}/cmdline" 2>/dev/null | tr '\0' ' ')
                if echo "$CMD" | grep -q "python\|\.py"; then
                    kill "$pid" 2>/dev/null
                fi
            fi
        done
    done
    sleep 1

    # Reinstalar scripts si no existen o están vacíos
    if [[ ! -s "$SCRIPT" ]]; then
        echo -e "${YELLOW}  [*] Regenerando scripts...${NC}"
        install_all_py
    fi

    # Verificar sintaxis Python antes de lanzar
    if ! python3 -m py_compile "$SCRIPT" 2>/dev/null; then
        echo -e "${RED}  [!!] Error de sintaxis — regenerando...${NC}"
        install_all_py
    fi

    # Lanzar
    nohup python3 "$SCRIPT" >> "${WS_LOG}" 2>&1 &
    local NEWPID=$!
    echo "$NEWPID" > "$PIDFILE"
    sleep 2

    # Verificar que sigue corriendo
    if kill -0 "$NEWPID" 2>/dev/null; then
        echo ""
        echo -e "${GREEN}  [✓] ${NAME} ACTIVO (PID: ${NEWPID})${NC}"
        echo ""
        for p in $PORTS; do
            echo -e "  ${CYAN}[*]${NC} python3 : ${YELLOW}${p}${NC}   $(port_working $p)"
            iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null
        done
    else
        echo ""
        echo -e "${RED}  [✗] ${NAME} no pudo iniciarse${NC}"
        echo ""
        echo -e "${YELLOW}  ── Últimas líneas del log ──${NC}"
        tail -15 "${WS_LOG}" 2>/dev/null
        echo ""
        echo -e "${YELLOW}  Causas comunes:${NC}"
        echo -e "  • Puerto ya en uso → detén otros procesos primero [7]"
        echo -e "  • Permisos → ejecutar como root"
    fi
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   WIZARD INTERACTIVO
# ─────────────────────────────────────────────────────────────
wizard_setup() {
    clear
    echo ""
    echo -e "${BMAGENTA}  🍄  INSTALACION DE PROTOCOLOS  🍄${NC}"
    sep2
    echo ""

    sep
    echo -e "${WHITE}          Puerto Principal, para Proxy WS/Directo${NC}"
    sep
    echo ""
    local CUR_PORTS; CUR_PORTS=$(cfg_get "ports" 2>/dev/null)
    [[ -n "$CUR_PORTS" ]] && \
        echo -e "${GREEN}  Puerto python: ${YELLOW}${CUR_PORTS} ${GREEN}VALIDO${NC}" || \
        echo -e "${GREEN}  Puerto python: ${YELLOW}80 ${GREEN}(por defecto)${NC}"
    echo ""
    echo -e "${WHITE}  Puertos WS (separa con coma, ej: 80,8080,3128):${NC}"
    echo -ne "${MAGENTA}  -> : ${NC}"
    read -r WS_PORT
    WS_PORT="${WS_PORT:-80}"
    echo ""
    echo -e "${GREEN}  Puerto python: ${YELLOW}${WS_PORT} ${GREEN}VALIDO${NC}"
    echo ""

    sep
    echo -e "${WHITE}          Puerto Local SSH/DROPBEAR/OPENVPN${NC}"
    sep
    echo ""
    local CUR_LOCAL; CUR_LOCAL=$(cfg_get "local_port" 2>/dev/null)
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

    sep
    echo -e "${GREEN}  RESPONDE DE CABECERA ${YELLOW}(101,200,403,500,etc)${NC}"
    sep
    echo ""
    echo -e "${WHITE}          Response personalizado (enter por defecto 200)${NC}"
    echo -e "${WHITE}          NOTA : Para OVER WEBSOCKET escribe ${CYAN}[ 101 ]${NC}"
    echo ""
    local CUR_RESP; CUR_RESP=$(cfg_get "response" 2>/dev/null)
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
    local CUR_CUSTOM; CUR_CUSTOM=$(cfg_get "custom_resp" 2>/dev/null)
    [[ -n "$CUR_CUSTOM" ]] && \
        echo -e "${GREEN}  CABECERA : ${YELLOW}${CUR_CUSTOM}${NC}" || \
        echo -e "${GREEN}  CABECERA : ${YELLOW}DEFAULT_HOST${NC}"
    echo ""
    echo -ne "${MAGENTA}  -> : ${NC}"
    read -r CUSTOM_RESP
    echo ""

    sep
    echo -e "${WHITE}                Introdusca su Mini-Banner${NC}"
    sep
    echo ""
    echo -e "${WHITE}          Introduzca un texto [NORMAL] o en [HTML]${NC}"
    local CUR_BANNER; CUR_BANNER=$(cfg_get "banner" 2>/dev/null)
    [[ -n "$CUR_BANNER" ]] && \
        echo -e "${GREEN}  -> : ${CYAN}${CUR_BANNER}${NC}" || \
        echo -e "${GREEN}  -> : ${CYAN}yourvpsmaster${NC}"
    echo -ne "${MAGENTA}  -> : ${NC}"
    read -r BANNER
    BANNER="${BANNER:-yourvpsmaster}"
    echo ""

    local PORTS_JSON
    PORTS_JSON=$(python3 -c "
import json
raw = '${WS_PORT}'
parts = [int(x.strip()) for x in raw.replace(',',' ').split() if x.strip().isdigit()]
if not parts: parts = [80]
print(json.dumps(parts))
" 2>/dev/null || echo "[80]")

    cfg_save "$PORTS_JSON" "$LOCAL_PORT" "$RESPONSE" "$CUSTOM_RESP" "$BANNER"
    install_all_py

    for p in $(echo "$WS_PORT" | tr ',' ' '); do
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null
    done
    iptables -I INPUT -p tcp --dport "$LOCAL_PORT" -j ACCEPT 2>/dev/null
    config_set "PROTO_WS" "1"

    echo -e "${GREEN}  [✓] Configuración guardada${NC}"
    echo ""
    press_enter
    main_launch_menu
}

# ─────────────────────────────────────────────────────────────
#   MENÚ PRINCIPAL — réplica de la captura de pantalla
# ─────────────────────────────────────────────────────────────
main_launch_menu() {
    while true; do
        clear
        echo ""
        echo -e "${BMAGENTA}  🍄  INSTALACION DE PROTOCOLOS  🍄${NC}"
        sep2
        echo ""

        # Puertos con estado WORKING / STOPPED
        local PORTS; PORTS=$(cfg_get "ports")
        if [[ -n "$PORTS" ]]; then
            local IDX=1
            for p in $PORTS; do
                echo -e "  ${CYAN}[${IDX}]${NC} ➪ python3 : ${YELLOW}${p}${NC}   $(port_working $p)"
                IDX=$((IDX+1))
            done
        else
            echo -e "  ${YELLOW}  Sin puertos — ejecuta el wizard (opción 9)${NC}"
        fi

        echo ""
        sep
        echo ""
        # Las 6 opciones — igual que la captura
        echo -e "  ${CYAN}[1]${NC} > Socks Python ${WHITE}SIMPLE     ${NC}  $(mode_status simple)"
        echo -e "  ${CYAN}[2]${NC} > Socks Python ${WHITE}SEGURO     ${NC}  $(mode_status seguro)"
        echo -e "  ${CYAN}[3]${NC} > Socks Python ${WHITE}DIRETO (WS)${NC}  $(mode_status direto)"
        echo -e "  ${CYAN}[4]${NC} > Socks Python ${WHITE}OPENVPN    ${NC}  $(mode_status ovpn)"
        echo -e "  ${CYAN}[5]${NC} > Socks Python ${WHITE}GETTUNEL   ${NC}  $(mode_status gettunel)"
        echo -e "  ${CYAN}[6]${NC} > Socks Python ${WHITE}TCP BYPASS ${NC}  $(mode_status tcpbypass)"
        echo ""
        sep
        echo ""
        echo -e "  ${CYAN}[7]${NC} > ANULAR TODOS   ${CYAN}[8]${NC} > ELIMINAR UN PUERTO"
        echo ""
        sep
        echo -e "  ${CYAN}[9]${NC}  > Reconfigurar (wizard)    ${CYAN}[10]${NC} > Agregar puerto"
        echo -e "  ${CYAN}[11]${NC} > Ver logs                 ${CYAN}[12]${NC} > Test conexión"
        echo ""
        sep
        echo -e "  ${CYAN}[0]${NC} >  $(echo -e "${BRED}VOLVER${NC}")"
        sep2
        echo -ne "${MAGENTA}  ► Opcion : ${NC}"
        read -r opt

        case "$opt" in
            1) launch_mode "Socks Python SIMPLE"      "${WS_DIR}/simple.py"    "simple"    ;;
            2) launch_mode "Socks Python SEGURO"      "${WS_DIR}/seguro.py"    "seguro"    ;;
            3) launch_mode "Socks Python DIRETO (WS)" "${WS_DIR}/direto.py"    "direto"    ;;
            4) launch_mode "Socks Python OPENVPN"     "${WS_DIR}/ovpn.py"      "ovpn"      ;;
            5) launch_mode "Socks Python GETTUNEL"    "${WS_DIR}/gettunel.py"  "gettunel"  ;;
            6) launch_mode "Socks Python TCP BYPASS"  "${WS_DIR}/tcpbypass.py" "tcpbypass" ;;
            7)  stop_all_proxies ;;
            8)  remove_port ;;
            9)  wizard_setup; return ;;
            10) add_port ;;
            11) view_logs ;;
            12) test_connection ;;
            0)  return ;;
            *)  echo -e "${RED}  Opción inválida${NC}"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────
#   [7] ANULAR TODOS
# ─────────────────────────────────────────────────────────────
stop_all_proxies() {
    echo -e "${RED}  [*] Deteniendo todos los proxies...${NC}"
    for MODE in simple seguro direto ovpn gettunel tcpbypass; do
        local PF="${PID_DIR}/ws_${MODE}.pid"
        if [[ -f "$PF" ]]; then
            local PID; PID=$(cat "$PF" 2>/dev/null)
            [[ -n "$PID" ]] && kill "$PID" 2>/dev/null && echo -e "  ${YELLOW}Detenido: ${MODE}${NC}"
            rm -f "$PF"
        fi
    done
    # Matar cualquier .py del directorio WS que quede
    pkill -f "${WS_DIR}/" 2>/dev/null || true
    config_set "PROTO_WS" "0"
    echo -e "${RED}  [✓] Todos los proxies detenidos${NC}"
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   [8] ELIMINAR UN PUERTO
# ─────────────────────────────────────────────────────────────
remove_port() {
    local PORTS; PORTS=$(cfg_get "ports")
    echo -e "${CYAN}  Puertos actuales: ${YELLOW}${PORTS}${NC}"
    echo ""
    echo -ne "${MAGENTA}  ► Puerto a eliminar: ${NC}"
    read -r DP
    [[ ! "$DP" =~ ^[0-9]+$ ]] && { echo -e "${RED}  Inválido${NC}"; sleep 2; return; }
    python3 - << PYEOF
import json
f = "${WS_CONF}"
try:
    with open(f) as fp: d = json.load(fp)
except:
    print("Config no encontrada"); exit()
p = int(${DP})
if p in d["ports"]:
    d["ports"].remove(p)
    with open(f,"w") as fp: json.dump(d, fp, indent=4)
    print(f"  Puerto {p} eliminado")
else:
    print(f"  Puerto {p} no encontrado")
PYEOF
    echo -e "${YELLOW}  Reinicia el modo activo para aplicar${NC}"
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   [10] AGREGAR PUERTO
# ─────────────────────────────────────────────────────────────
add_port() {
    echo -ne "${MAGENTA}  ► Nuevo puerto: ${NC}"
    read -r NP
    [[ ! "$NP" =~ ^[0-9]+$ ]] && { echo -e "${RED}  Inválido${NC}"; sleep 2; return; }
    python3 - << PYEOF
import json
f = "${WS_CONF}"
try:
    with open(f) as fp: d = json.load(fp)
except:
    d = {"ports":[80],"local_port":22,"local_host":"127.0.0.1",
         "response":"101","custom_resp":"","banner":"yourvpsmaster","buffer":65536}
p = int(${NP})
if p not in d["ports"]:
    d["ports"].append(p); d["ports"].sort()
    with open(f,"w") as fp: json.dump(d, fp, indent=4)
    print(f"  [OK] Puerto {p} agregado")
else:
    print(f"  Puerto {p} ya existe")
PYEOF
    iptables -I INPUT -p tcp --dport "$NP" -j ACCEPT 2>/dev/null
    echo -e "${YELLOW}  Reinicia el modo activo para aplicar${NC}"
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   [11] VER LOGS
# ─────────────────────────────────────────────────────────────
view_logs() {
    clear
    echo -e "${CYAN}  ws_proxy.log — últimas 50 líneas:${NC}"
    echo ""
    [[ -f "${WS_LOG}" ]] && tail -50 "${WS_LOG}" || \
        echo -e "${YELLOW}  Sin logs. Inicia un modo primero.${NC}"
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   [12] TEST DE CONEXIÓN
# ─────────────────────────────────────────────────────────────
test_connection() {
    clear
    echo -e "${BMAGENTA}  🍄 TEST DE CONEXIÓN PROXY  🍄${NC}"
    sep2
    echo ""
    local PORTS; PORTS=$(cfg_get "ports")
    local LOCAL; LOCAL=$(cfg_get "local_port"); LOCAL="${LOCAL:-22}"
    local RESP;  RESP=$(cfg_get "response");   RESP="${RESP:-101}"

    echo -e "  ${GREEN}Puerto SSH destino : ${YELLOW}${LOCAL}${NC}"
    echo -e "  ${GREEN}Respuesta esperada : ${CYAN}HTTP ${RESP}${NC}"
    echo ""

    # Test SSH
    echo -ne "  ${WHITE}SSH en :${LOCAL} ...${NC} "
    if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/${LOCAL}" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[NO DISPONIBLE]${NC}"
        echo -e "  ${YELLOW}→ systemctl start ssh${NC}"
    fi
    echo ""

    # Test proxy por puerto
    for p in $PORTS; do
        echo -ne "  ${WHITE}Proxy en :${p} ...${NC} "
        if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/${p}" 2>/dev/null; then
            # Enviar request HTTP y leer respuesta
            local GOT_RESP
            GOT_RESP=$(timeout 3 python3 -c "
import socket
try:
    s = socket.create_connection(('127.0.0.1', ${p}), timeout=3)
    s.send(b'GET / HTTP/1.1\r\nHost: t\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
    s.settimeout(3)
    r = s.recv(200).decode(errors='ignore')
    print(r.split('\r\n')[0])
    s.close()
except Exception as e:
    print(f'ERR:{e}')
" 2>/dev/null)
            if echo "$GOT_RESP" | grep -q "HTTP"; then
                echo -e "${GREEN}${GOT_RESP}${NC}"
            else
                echo -e "${YELLOW}Escuchando pero sin respuesta HTTP${NC}"
            fi
        else
            echo -e "${RED}[ STOPPED ] — Inicia un modo (1-6)${NC}"
        fi
    done

    echo ""
    press_enter
}

# ─────────────────────────────────────────────────────────────
#   ENTRADA PRINCIPAL
# ─────────────────────────────────────────────────────────────
if [[ -f "$WS_CONF" ]]; then
    [[ ! -f "${WS_DIR}/simple.py" ]] && install_all_py
    main_launch_menu
else
    wizard_setup
fi
