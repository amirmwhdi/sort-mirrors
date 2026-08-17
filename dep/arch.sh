#!/bin/bash

check_curl() {
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required."; return 1; }
}

arch_main() {
    local version="$1"
    local pretty_name="$2"
    local file="/etc/pacman.d/mirrorlist"
    
    local arch=$(uname -m)
    
    echo "=== Arch Linux Mirror Updater ==="
    echo "Distribution: $pretty_name (Version: $version)"
    echo "Architecture: $arch"
    echo ""
    
    check_curl || return 1
    
    if [ ! -f "$file" ]; then
        echo "ERROR: File $file does not exist!"
        return 1
    fi
    
    echo "Fetching latest mirror list from Arch Linux..."
    local mirrors=$(curl -s "https://archlinux.org/mirrorlist/all/" | \
        grep -Eo 'Server = .*\$repo/os/\$arch' | \
        sed 's|Server = ||g; s|\$repo/os/\$arch||g' | \
        sort -u)
    
    if [ -z "$mirrors" ]; then
        echo "WARN: Arch mirrorlist parsing failed. Falling back to raw text..."
        mirrors=$(curl -s "https://raw.githubusercontent.com/archlinux/arch-mirrorlist/master/mirrorlist" | \
            grep -Eo 'Server = .*\$repo/os/\$arch' | \
            sed 's|Server = ||g; s|\$repo/os/\$arch||g' | \
            sort -u)
    fi
    
    if [ -z "$mirrors" ]; then
        echo "ERROR: Could not fetch mirror list."
        return 1
    fi
    
    local total=$(echo "$mirrors" | wc -l)
    echo "Testing $total mirrors (this may take a moment)..."
    
    export arch
    
    local fastest=$(echo "$mirrors" | \
        xargs -P 10 -I {} bash -c '
            url="{}"
            time=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 2 --max-time 5 "${url}core/os/${arch}/core.db" 2>/dev/null)
            if [ -n "$time" ] && [ "$time" != "0.000" ]; then
                echo "$time $url"
            fi
        ' | sort -n | head -n 5)
    
    if [ -z "$fastest" ]; then
        echo "ERROR: No mirrors responded."
        return 1
    fi
    
    echo ""
    echo "=== Fastest mirrors found ==="
    echo "$fastest" | awk '{print $2, "("$1"s)"}' | nl
    echo ""
    
    local best_mirror=$(echo "$fastest" | head -1 | awk '{print $2}')
    echo "Fastest mirror: $best_mirror"
    echo ""
    
    echo "Do you want to backup and replace the mirrorlist? (y/n)"
    read -r answer
    
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        echo "Creating backup: ${file}.backup"
        sudo cp "$file" "${file}.backup"
        
        echo "$fastest" | awk '{print "Server = " $2 "$repo/os/$arch"}' | sudo tee "$file" > /dev/null
        
        echo "SUCCESS: $file updated with fastest mirrors."
        echo "Backup: ${file}.backup"
        echo "Run 'sudo pacman -Syyu' to sync databases."
    else
        echo "No changes made."
    fi
}

export -f arch_main