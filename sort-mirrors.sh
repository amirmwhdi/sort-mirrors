#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/dep"

if [ ! -f /etc/os-release ]; then
    echo "ERROR: /etc/os-release not found. This script requires a modern Linux distribution."
    exit 1
fi

get_os_var() {
    grep -E "^$1=" /etc/os-release | cut -d= -f2- | tr -d '"' | head -n1
}

ID=$(get_os_var ID)
VERSION_ID=$(get_os_var VERSION_ID)
PRETTY_NAME=$(get_os_var PRETTY_NAME)
VERSION_CODENAME=$(get_os_var VERSION_CODENAME)

[ -z "$VERSION_CODENAME" ] && VERSION_CODENAME=$(get_os_var UBUNTU_CODENAME)
[ -z "$VERSION_CODENAME" ] && VERSION_CODENAME=$(get_os_var DEBIAN_CODENAME)

case "$ID" in
    ubuntu|linuxmint|pop|elementary|neon|zorin|kde)
        DISTRO_ID="ubuntu"
        ;;
    debian|kali|mx|raspbian|deepin|pardus)
        DISTRO_ID="debian"
        ;;
    cachyos)
        DISTRO_ID="cachyos"
        ;;
    arch|manjaro|endeavouros|garuda|artix|arcolinux)
        DISTRO_ID="arch"
        ;;
    *)
        DISTRO_ID="$ID"
        ;;
esac

export VERSION_ID PRETTY_NAME VERSION_CODENAME

load_modules() {
    local distro_id="$1"
    local module_file=""
    
    case "$distro_id" in
        ubuntu|debian|arch|cachyos)
            module_file="$MODULE_DIR/$distro_id.sh"
            ;;
        *)
            echo "ERROR: Unsupported distribution: $distro_id"
            echo "This script supports Ubuntu, Debian, Arch, and CachyOS (and their derivatives) only."
            exit 1
            ;;
    esac
    
    if [ -f "$module_file" ]; then
        source "$module_file"
    else
        echo "ERROR: Module file not found: $module_file"
        exit 1
    fi
}

echo "Distribution ID: $DISTRO_ID"
echo "Version: $VERSION_ID"
echo "Pretty name: $PRETTY_NAME"
echo ""

load_modules "$DISTRO_ID"

case "$DISTRO_ID" in
    ubuntu) ubuntu_main "$VERSION_ID" "$PRETTY_NAME" ;;
    debian) debian_main "$VERSION_ID" "$PRETTY_NAME" ;;
    cachyos) cachyos_main "$VERSION_ID" "$PRETTY_NAME" ;;
    arch)   arch_main "$VERSION_ID" "$PRETTY_NAME" ;;
esac

echo ""
echo "========================================="
echo "Mirror manager completed successfully."