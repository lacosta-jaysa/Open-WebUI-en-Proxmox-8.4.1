#!/usr/bin/env bash

# ============================================================================
# Open WebUI Update Script for Proxmox 8.4.1
# Repository: https://github.com/lacosta-jaysa/Open-WebUI-en-Proxmox-8.4.1
# Author: lacosta-jaysa
# License: MIT
#
# Uso:
#   Desde el HOST: bash update.sh <CTID>
#   Desde el LXC:  bash update.sh
# ============================================================================

set -euo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

function msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

function msg_ok() {
    echo -e "${GREEN}[✓]${NC} $1"
}

function msg_error() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
}

function header_info() {
clear
cat <<"EOF"     
   ____                      _       __     __    __  ______
  / __ \____  ___  ____     | |     / /__  / /_  / / / /  _/
 / / / / __ \/ _ \/ __ \    | | /| / / _ \/ __ \/ / / // /
/ /_/ / /_/ /  __/ / / /    | |/ |/ /  __/ /_/ / /_/ // /
\____/ .___/\___/_/ /_/     |__/|__/\___/_.___/\____/___/
    /_/
    
    ╔═══════════════════════════════════════════════════════╗
    ║        ACTUALIZACIÓN DE OPEN WEBUI                    ║
    ║  github.com/lacosta-jaysa/Open-WebUI-en-Proxmox-8.4.1 ║
    ╚═══════════════════════════════════════════════════════╝
EOF
echo ""
}

function check_installation() {
    if [[ ! -d /opt/open-webui ]]; then
        msg_error "No se encontró instalación de Open WebUI en /opt/open-webui"
    fi
}

function backup_data() {
    msg_info "Creando backup de datos..."
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="/opt/openwebui-backups"
    
    mkdir -p "$backup_dir"
    
    if [[ -d /opt/open-webui/backend/data ]]; then
        tar -czf "${backup_dir}/openwebui-data-${timestamp}.tar.gz" \
            -C /opt/open-webui/backend data/ 2>/dev/null || true
        msg_ok "Backup creado: ${backup_dir}/openwebui-data-${timestamp}.tar.gz"
    else
        msg_info "No hay datos para respaldar (instalación nueva)"
    fi
    
    # Mantener solo los últimos 5 backups
    cd "$backup_dir"
    ls -t openwebui-data-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm --
}

function stop_service() {
    msg_info "Deteniendo servicio de Open WebUI..."
    systemctl stop open-webui.service
    sleep 2
    msg_ok "Servicio detenido"
}

function update_repository() {
    msg_info "Actualizando código desde GitHub..."
    cd /opt/open-webui
    
    # Guardar cambios locales si existen
    if git status --porcelain | grep -q '^'; then
        msg_info "Guardando cambios locales..."
        git stash save "Auto-stash before update $(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    
    # Obtener última versión
    git fetch origin main
    local local_hash=$(git rev-parse HEAD)
    local remote_hash=$(git rev-parse origin/main)
    
    if [[ "$local_hash" == "$remote_hash" ]]; then
        msg_ok "El código ya está actualizado (commit: ${local_hash:0:8})"
        return 1
    else
        msg_info "Nueva versión disponible"
        msg_info "Local:  ${local_hash:0:8}"
        msg_info "Remoto: ${remote_hash:0:8}"
        
        git pull origin main || msg_error "Fallo al actualizar desde GitHub"
        msg_ok "Código actualizado exitosamente"
        return 0
    fi
}

function update_frontend() {
    msg_info "Actualizando dependencias del frontend..."
    cd /opt/open-webui
    npm install || msg_error "Fallo al instalar dependencias de Node.js"
    msg_ok "Dependencias actualizadas"
    
    msg_info "Reconstruyendo frontend (esto puede tardar varios minutos)..."
    echo -e "${YELLOW}[!]${NC} Por favor, ten paciencia durante este proceso..."
    
    export NODE_OPTIONS="--max-old-space-size=4096"
    npm run build || msg_error "Fallo al construir frontend"
    msg_ok "Frontend reconstruido exitosamente"
}

function update_backend() {
    msg_info "Actualizando dependencias del backend..."
    cd /opt/open-webui/backend
    pip3 install -r requirements.txt -U --break-system-packages || msg_error "Fallo al actualizar backend"
    msg_ok "Backend actualizado"
}

function start_service() {
    msg_info "Iniciando servicio de Open WebUI..."
    systemctl start open-webui.service
    sleep 5
    
    if systemctl is-active --quiet open-webui.service; then
        msg_ok "Servicio iniciado correctamente"
    else
        msg_error "El servicio no pudo iniciarse. Ver logs con: journalctl -u open-webui.service -n 50"
    fi
}

function check_version() {
    cd /opt/open-webui
    local version=$(git describe --tags --always 2>/dev/null || echo "unknown")
    local commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                  INFORMACIÓN DE LA VERSIÓN                    ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "  Versión:  ${CYAN}${version}${NC}"
    echo -e "  Commit:   ${CYAN}${commit}${NC}"
    echo -e "  Rama:     ${CYAN}${branch}${NC}"
    echo ""
}

function show_logs_option() {
    echo ""
    read -p "¿Deseas ver los logs del servicio? (s/N): " show_logs
    if [[ $show_logs =~ ^[Ss]$ ]]; then
        echo ""
        msg_info "Mostrando últimas 30 líneas de logs..."
        echo ""
        journalctl -u open-webui.service -n 30 --no-pager
    fi
}

function get_container_ip() {
    ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "N/A"
}

function update_inside_container() {
    header_info
    check_installation
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    msg_info "Iniciando actualización de Open WebUI..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    backup_data
    stop_service
    
    if update_repository; then
        # Hay actualizaciones, reconstruir todo
        update_frontend
        update_backend
    else
        # No hay actualizaciones de código, solo verificar dependencias
        msg_info "Verificando actualizaciones de dependencias..."
        update_backend
    fi
    
    start_service
    check_version
    
    local ip=$(get_container_ip)
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║              ¡ACTUALIZACIÓN COMPLETADA!                       ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${GREEN}✓ Open WebUI actualizado correctamente${NC}"
    echo ""
    echo -e "  🌐 URL de acceso:"
    echo -e "     ${CYAN}http://${ip}:8080${NC}"
    echo ""
    
    show_logs_option
}

function update_from_host() {
    local ctid=$1
    
    header_info
    
    if ! pct status $ctid &>/dev/null; then
        msg_error "El contenedor $ctid no existe"
    fi
    
    if ! pct status $ctid | grep -q "running"; then
        msg_error "El contenedor $ctid no está en ejecución. Inícialo con: pct start $ctid"
    fi
    
    msg_info "Ejecutando actualización en contenedor $ctid..."
    echo ""
    
    # Copiar este script al contenedor y ejecutarlo
    pct exec $ctid -- bash -c "$(cat $0)" -- --internal || msg_error "Fallo al ejecutar actualización en el contenedor"
    
    msg_ok "Actualización completada en contenedor $ctid"
}

# ============================================================================
# FUNCIÓN PRINCIPAL
# ============================================================================

main() {
    # Detectar si se ejecuta desde el host o desde el contenedor
    if [[ "${1:-}" == "--internal" ]]; then
        # Ejecutándose dentro del contenedor
        update_inside_container
    elif [[ $# -eq 1 && "$1" =~ ^[0-9]+$ ]]; then
        # Ejecutándose desde el host con CTID
        if ! command -v pct &> /dev/null; then
            msg_error "Este script debe ejecutarse en el HOST de Proxmox cuando se especifica un CTID"
        fi
        update_from_host "$1"
    elif [[ $# -eq 0 ]]; then
        # Sin argumentos, asumir que se ejecuta dentro del contenedor
        update_inside_container
    else
        header_info
        echo "Uso:"
        echo "  Desde el HOST de Proxmox:"
        echo "    bash update.sh <CTID>"
        echo ""
        echo "  Desde dentro del contenedor LXC:"
        echo "    bash update.sh"
        echo ""
        exit 1
    fi
}

# Ejecutar script principal
main "$@"
