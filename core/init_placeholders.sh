#!/bin/bash
# Placeholder generator for remaining protocol scripts
INSTALL_DIR="/opt/yourvpsmaster"

make_placeholder() {
    local FILE="$1"
    local TITLE="$2"
    cat > "$FILE" << PLEOF
#!/bin/bash
INSTALL_DIR="/opt/yourvpsmaster"
source "\${INSTALL_DIR}/core/lib.sh"
clear
show_header
echo ""
echo -e "\${BMAGENTA}  🍄  ${TITLE}  🍄\${NC}"
echo -e "\${YELLOW}  ════════════════════════════════════════════════════\${NC}"
echo ""
echo -e "\${CYAN}  Módulo en desarrollo / instalación...\${NC}"
echo ""
press_enter
PLEOF
    chmod +x "$FILE"
}

make_placeholder "${INSTALL_DIR}/protocols/dropbear.sh"     "DROPBEAR SSH"
make_placeholder "${INSTALL_DIR}/protocols/openvpn.sh"      "OPENVPN"
make_placeholder "${INSTALL_DIR}/protocols/ssl_tls.sh"      "SSL/TLS"
make_placeholder "${INSTALL_DIR}/protocols/shadowsocks.sh"  "SHADOWSOCKS-R"
make_placeholder "${INSTALL_DIR}/protocols/squid.sh"        "SQUID PROXY"
make_placeholder "${INSTALL_DIR}/protocols/v2ray.sh"        "V2RAY / XRAY"
make_placeholder "${INSTALL_DIR}/protocols/clash.sh"        "CFA CLASH"
make_placeholder "${INSTALL_DIR}/protocols/trojan.sh"       "TROJAN-GO"
make_placeholder "${INSTALL_DIR}/protocols/psiphon.sh"      "PSIPHON SERVER"
make_placeholder "${INSTALL_DIR}/protocols/ssl_python.sh"   "SSL→PYTHON"
make_placeholder "${INSTALL_DIR}/protocols/sslh.sh"         "SSLH MULTIPLEX"
make_placeholder "${INSTALL_DIR}/protocols/socks5.sh"       "SOCKS5"
make_placeholder "${INSTALL_DIR}/protocols/udp_proto.sh"    "PROTOCOLOS UDP"
make_placeholder "${INSTALL_DIR}/protocols/brook.sh"        "BROOK SERVER"
make_placeholder "${INSTALL_DIR}/tools/webmin.sh"           "WEBMIN"
make_placeholder "${INSTALL_DIR}/tools/block_torrent.sh"    "BLOCK TORRENT"
make_placeholder "${INSTALL_DIR}/tools/fail2ban.sh"         "FAIL2BAN"
make_placeholder "${INSTALL_DIR}/tools/file_manager.sh"     "ARCHIVO ONLINE"
make_placeholder "${INSTALL_DIR}/tools/speedtest.sh"        "SPEEDTEST"
make_placeholder "${INSTALL_DIR}/tools/block_ads.sh"        "BLOCK ADS"
make_placeholder "${INSTALL_DIR}/tools/dns_custom.sh"       "DNS CUSTOM NETFLIX"
make_placeholder "${INSTALL_DIR}/tools/extras.sh"           "HERRAMIENTAS EXTRAS"
make_placeholder "${INSTALL_DIR}/tools/change_passwd.sh"    "CAMBIAR PASSWD ROOT"
make_placeholder "${INSTALL_DIR}/tools/atoken.sh"           "ATOKEN APP MODS"
make_placeholder "${INSTALL_DIR}/tools/optimize_vps.sh"     "OPTIMIZAR VPS"
make_placeholder "${INSTALL_DIR}/tools/counter.sh"          "CONTADOR ONLINE"
