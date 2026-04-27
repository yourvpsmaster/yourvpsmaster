#!/bin/bash
# ============================================================
#   YOURVPSMASTER - CONFIGURAR NGINX (Puerto 80 → 101)
# ============================================================
INSTALL_DIR="/opt/yourvpsmaster"
source "${INSTALL_DIR}/core/lib.sh"

configure_nginx() {
    echo -e "${CYAN}  [*] Configurando Nginx...${NC}"
    apt-get install -y -qq nginx 2>/dev/null

    # Configuración Nginx con WebSocket upgrade (respuesta 101)
    cat > /etc/nginx/sites-available/yourvpsmaster << 'NGXEOF'
# YourVPSMaster Nginx Config
# Puerto 80: WebSocket proxy (respuesta 101) + archivo manager (81)

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # WebSocket Proxy → SSH via WebSocket Python
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # Health check
    location /ping {
        return 200 "yourvpsmaster-ok\n";
        add_header Content-Type text/plain;
    }
}

# Archivo online en puerto 81
server {
    listen 81;
    server_name _;
    root /opt/yourvpsmaster/public;
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;

    location / {
        try_files $uri $uri/ =404;
    }
}
NGXEOF

    mkdir -p /opt/yourvpsmaster/public

    # Habilitar site
    ln -sf /etc/nginx/sites-available/yourvpsmaster /etc/nginx/sites-enabled/yourvpsmaster 2>/dev/null
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null

    nginx -t 2>/dev/null && systemctl restart nginx && \
        echo -e "${GREEN}  [✓] Nginx configurado${NC}" || \
        echo -e "${YELLOW}  [!] Error en config Nginx${NC}"
}

configure_nginx
press_enter
