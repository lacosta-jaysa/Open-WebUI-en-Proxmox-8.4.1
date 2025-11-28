#!/usr/bin/env bash

# Open WebUI Update Script for Proxmox 8.4.1
# Repository: https://github.com/lacosta-jaysa/Open-WebUI-en-Proxmox-8.4.1
# Author: lacosta-jaysa
# License: MIT

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

function msg_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

function msg_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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
    
    Script de Actualización - Open WebUI
    Repository: github.com/lacosta-jaysa/Open-WebUI-en-Proxmox-8.4.1
EOF
echo ""
}

function check_installation() {
    if [[ ! -d /opt/open-webui ]]; then
        msg_error "No se encontró instalación de Open WebUI en /opt/open-webui"
        echo ""
        echo "Si estás ejecutando esto desde el host de Proxmox, necesitas especificar el ID del contenedor:"
        echo "  bash update.sh <CTID>"
        echo ""
        exit 1
    fi
}

function backup_data() {
    msg_info "Creando backup de datos..."
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="/opt/open-webui-backup-${timestamp}"
    
    if [[ -d /opt/open-webui/backend/data ]]; then
        cp -r /opt/open-webui/backend/data "$backup_dir"
        msg_ok "Backup creado en: $backup_dir"
    else
        msg_info "No hay datos para respaldar"
    fi
}

function stop_service() {
    msg_info "Deteniendo servicio de Open WebUI..."
    systemctl stop open-webui.service
    msg_ok "Servicio detenido"
}

function update_repository() {
    msg_info "Actualizando código desde GitHub..."
    cd /opt/open-webui
    
    # Guardar cambios locales si existen
    git stash save "Auto-stash before update $(date +%Y%m%d_%H%M%S)" 2>/dev/null
    
    # Obtener última versión
    local output=$(git pull --no-rebase 2>&1)
    
    if echo "$output" | grep -q "Already up to date"; then
        msg_ok "El código ya está actualizado"
        return 1
    else
        msg_ok "Código actualizado desde repositorio"
        return 0
    fi
}

function update_frontend() {
    msg_info "Actualizando dependencias del frontend..."
    cd /opt/open-webui
    npm install
    msg_ok "Dependencias actualizadas"
    
    msg_info "Reconstruyendo frontend (esto puede tardar varios minutos)..."
    export NODE_OPTIONS="--max-old-space-size=4096"
    npm run build
    msg_ok "Frontend reconstruido"
}

function update_backend() {
    msg_info "Actualizando dependencias del backend..."
    cd /opt/open-webui/backend
    pip3 install -r requirements.txt -U --break-system-packages
    msg_ok "Backend actualizado"
}

function start_service() {
    msg_info "Iniciando servicio de Open WebUI..."
    systemctl start open-webui.service
    sleep 3
    
    if systemctl is-active --quiet open-webui.service; then
        msg_ok "Servicio iniciado correctamente"
    else
        msg_error "El servicio no pudo iniciarse. Revisa los logs con:"
        echo "  journalctl -u open-webui.service -n 50"
        exit 1
    fi
}

function check_version() {
    msg_info "Verificando versión instalada..."
    cd /opt/open-webui
    local version=$(git describe --tags --always)
    local commit=$(git rev-parse --short HEAD)
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}Versión actual:${NC} $version"
    echo -e "${GREEN}Commit:${NC} $commit"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

function show_logs() {
    echo ""
    read -p "¿Deseas ver los logs del servicio? (s/N): " show_logs
    if [[ $show_logs =~ ^[Ss]$ ]]; then
        journalctl -u open-webui.service -n 30 --no-pager
    fi
}

# Función principal
main() {
    header_info
    
    # Verificar si se ejecuta desde contenedor o host
    if [[ $1 =~ ^[0-9]+$ ]]; then
        msg_info "Ejecutando actualización en contenedor $1..."
        pct exec $1 -- bash -c "$(cat $0)"
        exit $?
    fi
    
    check_installation
    backup_data
    stop_service
    
    if update_repository; then
        update_frontend
        update_backend
    else
        msg_info "Verificando actualizaciones de dependencias..."
        update_backend
    fi
    
    start_service
    check_version
    
    echo ""
    msg_ok "¡Actualización completada exitosamente!"
    echo ""
    echo "Open WebUI está disponible en:"
    local ip=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo -e "  ${BLUE}http://${ip}:8080${NC}"
    echo ""
    
    show_logs
}

# Ejecutar script principal
main "$@"
