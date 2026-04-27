# 🍄 YourVPSMaster

Script de gestión VPS completo para **Ubuntu 22.04 LTS** con interfaz de terminal estilo neon.

## ✨ Características

- 🔐 **OpenSSH** — Gestión avanzada, puertos, MaxSessions
- 🌐 **WebSocket Proxy Python3** — Múltiples puertos simultáneos, respuesta HTTP 101
- 🐌 **SlowDNS (DNSTT)** — Compatible con HTTP Injector, KPN Tunnel
- 🚀 **BBR TCP** — Optimización de red (BBR + fq/cake/fq_codel)
- 🧅 **BadVPN UDP** — Puertos 7200, 7300 y personalizados
- 🔒 **SSL/TLS, OpenVPN, V2Ray, Trojan-Go, Shadowsocks-R**
- 🛡️ **Firewall iptables** — Gestión visual de reglas
- 👤 **Control de usuarios** — Crear, expirar, renovar, limitar
- 📁 **Archivo Online** — Nginx en puerto 81
- 📊 **Monitor VPS** — RAM, CPU, disco, uptime en tiempo real

---

## 🚀 Instalación

```bash
bash <(curl -sL https://raw.githubusercontent.com/yourvpsmaster/yourvpsmaster/main/install.sh)
```

> 

### Requisitos
- Ubuntu 22.04 LTS x86_64
- Acceso root
- Conexión a internet

---

## 📱 Uso con HTTP Injector (SlowDNS)

1. Instala el script en tu VPS
2. Ve a opción `[5] → [14] SlowDNS`
3. Selecciona `[1] Instalar/Configurar`
4. Configura tu dominio NS con `[7]`
5. Genera tu Public Key con `[2]`
6. Copia la Public Key con `[3]`
7. En **HTTP Injector**:
   - SSH Settings → DNS Tunnel (SlowDNS)
   - Activa SlowDNS
   - NameServer: tu registro NS
   - Public Key: pega la clave generada
   - SSH Host: IP de tu VPS
   - SSH Port: 22

---

## 🌐 WebSocket (HTTP Injector / HA Tunnel)

El proxy WebSocket responde **HTTP/1.1 101 Switching Protocols** en múltiples puertos.

```
Puertos por defecto: 80, 8080, 3128, 2082
```

En HTTP Injector:
- Tipo de conexión: WebSocket
- Host: IP de tu VPS
- Puerto: 80 (o cualquier otro activo)

---

## 📁 Estructura del Proyecto

```
yourvpsmaster/
├── install.sh              # Instalador principal
├── core/
│   ├── lib.sh             # Librería de colores y utilidades
│   ├── menu.sh            # Menú principal
│   ├── protocols_menu.sh  # Menú de protocolos
│   └── autostart.sh       # Auto-inicio de servicios
├── protocols/
│   ├── slowdns.sh         # SlowDNS / DNSTT
│   ├── proxy_python.sh    # WebSocket Python3
│   ├── openssh.sh         # OpenSSH manager
│   └── ...
└── tools/
    ├── user_control.sh    # Control de usuarios
    ├── badvpn.sh          # BadVPN UDP
    ├── bbr.sh             # BBR TCP optimizer
    ├── firewall.sh        # iptables manager
    └── ...
```

---

## 🔄 Actualizar

```bash
yourvpsmaster  # opción [06] → [1] Actualizar
```

## ❌ Desinstalar

```bash
yourvpsmaster  # opción [06] → [2] Desinstalar
```

---

## 📜 Licencia

MIT — Libre para uso personal y modificación.

---

> 🍄 **YourVPSMaster** — Hecho para simplificar la gestión de tu VPS
