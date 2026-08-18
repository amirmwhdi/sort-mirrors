#!/bin/bash

check_curl() {
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required." >&2; return 1; }
}

get_cachyos_mirrors() {
    echo "Fetching CachyOS mirror list..." >&2
    
    local mirror_list=$(curl -s --compressed -A "Mozilla/5.0" "https://packages.cachyos.org/mirrors" | \
        grep -aEo 'https?://[^"'\''<> ]+' | \
        grep -aiE 'cachyos|/repo' | \
        grep -avE 'packages.cachyos.org|dashboard.cachyos.org|w3.org|schemas|xmlns' | \
        sort -u)
    
    if [ -z "$mirror_list" ]; then
        echo "WARN: CachyOS parsing failed. Falling back to raw github list..." >&2
        mirror_list=$(curl -s "https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/master/cachyos-mirrorlist/mirrorlist" | \
            grep -aEo 'Server = .*\$repo/\$arch' | \
            sed 's|Server = ||g; s|\$repo/\$arch||g' | \
            sort -u)
    fi
    
    if [ -z "$mirror_list" ]; then
        echo "WARN: GitHub fallback failed. Using official CachyOS mirror..." >&2
        mirror_list="https://mirror.cachyos.org/repo/"
    fi
    
    echo "$mirror_list" | sed 's#/*$##' | sed 's#$#/#'
}

get_arch_mirrors() {
    echo "Fetching Arch Linux mirror list..." >&2
    
    local mirror_list=$(curl -s "https://archlinux.org/mirrorlist/all/" | \
        grep -aEo 'Server = .*\$repo/os/\$arch' | \
        sed 's|Server = ||g; s|\$repo/os/\$arch||g' | \
        sort -u)
    
    if [ -z "$mirror_list" ]; then
        echo "WARN: Arch mirrorlist parsing failed. Falling back to raw text..." >&2
        mirror_list=$(curl -s "https://raw.githubusercontent.com/archlinux/arch-mirrorlist/master/mirrorlist" | \
            grep -aEo 'Server = .*\$repo/os/\$arch' | \
            sed 's|Server = ||g; s|\$repo/os/\$arch||g' | \
            sort -u)
    fi
    
    if [ -z "$mirror_list" ]; then
        echo "WARN: Arch fallback failed. Using official Arch mirror..." >&2
        mirror_list="https://geo.mirror.pkgbuild.com/"
    fi
    
    echo "$mirror_list" | sed 's#/*$##' | sed 's#$#/#'
}

test_mirrors_speed() {
    local count="${1:-5}"
    local mirrors="$2"
    local test_path="$3"
    
    if [ -z "$mirrors" ]; then
        echo "ERROR: No mirrors found." >&2
        return 1
    fi
    
    local total=$(echo "$mirrors" | wc -l)
    echo "Testing $total mirrors..." >&2
    
    echo "$mirrors" | \
        xargs -P 10 -I {} bash -c '
            url="$1"
            tpath="$2"
            time=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 2 --max-time 5 "${url}${tpath}" 2>/dev/null)
            if [ -n "$time" ] && [ "$time" != "0.000" ]; then
                echo "$time $url"
            fi
        ' _ {} "$test_path" | \
        sort -n | \
        head -n "$count"
}

process_cachyos_mirrors() {
    local mirrors=$(get_cachyos_mirrors)
    local fastest=$(test_mirrors_speed 5 "$mirrors" "cachyos/x86_64/cachyos.db")
    
    if [ -z "$fastest" ]; then
        echo "ERROR: No CachyOS mirrors responded." >&2
        return 1
    fi
    
    echo ""
    echo "=== Fastest CachyOS mirrors found ==="
    echo "$fastest" | awk '{print $2, "("$1"s)"}' | nl
    echo ""
    
    local best_mirror=$(echo "$fastest" | head -1 | awk '{print $2}')
    echo "Fastest CachyOS mirror: $best_mirror"
    echo ""
    
    echo "Do you want to backup and replace the CachyOS mirrorlists? (y/n)"
    read -r answer
    
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        local mirror_files=(
            "/etc/pacman.d/cachyos-mirrorlist"
            "/etc/pacman.d/cachyos-v3-mirrorlist"
            "/etc/pacman.d/cachyos-v4-mirrorlist"
        )
        local mirror_content=$(echo "$fastest" | awk '{print "Server = " $2 "$repo/$arch"}')
        
        for file in "${mirror_files[@]}"; do
            if [ -f "$file" ]; then
                echo "Processing: $file"
                echo "Creating backup: ${file}.backup"
                sudo cp "$file" "${file}.backup"
                echo "$mirror_content" | sudo tee "$file" > /dev/null
            else
                echo "Skipping: $file (does not exist)"
            fi
        done
        echo "SUCCESS: CachyOS mirrorlists updated."
        return 0
    else
        echo "No changes made to CachyOS mirrorlists."
        return 1
    fi
}

process_arch_mirrors() {
    local mirrors=$(get_arch_mirrors)
    local fastest=$(test_mirrors_speed 5 "$mirrors" "core/os/x86_64/core.db")
    
    if [ -z "$fastest" ]; then
        echo "ERROR: No Arch Linux mirrors responded." >&2
        return 1
    fi
    
    echo ""
    echo "=== Fastest Arch Linux mirrors found ==="
    echo "$fastest" | awk '{print $2, "("$1"s)"}' | nl
    echo ""
    
    local best_mirror=$(echo "$fastest" | head -1 | awk '{print $2}')
    echo "Fastest Arch mirror: $best_mirror"
    echo ""
    
    echo "Do you want to backup and replace the Arch mirrorlist? (y/n)"
    read -r answer
    
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        local file="/etc/pacman.d/mirrorlist"
        if [ -f "$file" ]; then
            echo "Processing: $file"
            echo "Creating backup: ${file}.backup"
            sudo cp "$file" "${file}.backup"
            local mirror_content=$(echo "$fastest" | awk '{print "Server = " $2 "$repo/os/$arch"}')
            echo "$mirror_content" | sudo tee "$file" > /dev/null
            echo "SUCCESS: Arch mirrorlist updated."
            return 0
        else
            echo "ERROR: /etc/pacman.d/mirrorlist not found!" >&2
            return 1
        fi
    else
        echo "No changes made to Arch mirrorlist."
        return 1
    fi
}

cachyos_show_menu() {
    local options=("Only CachyOS Mirrors" "Only Arch Linux Mirrors" "Both")
    local selected=0
    local key

    echo -e "Select the mirrors you want to test and apply:\033[K"
    for i in "${!options[@]}"; do
        if [ $i -eq $selected ]; then
            echo -e " -> \033[7m ${options[$i]} \033[0m\033[K"
        else
            echo -e "    ${options[$i]}\033[K"
        fi
    done
    echo -e "(Use Up/Down arrows and Enter to select)\033[K"

    while true; do
        read -rsn1 key
        if [[ $key == $'\e' ]]; then
            read -rsn2 -t 1 seq
            case "$seq" in
                '[A') ((selected--)); [ $selected -lt 0 ] && selected=2 ;; # Up
                '[B') ((selected++)); [ $selected -gt 2 ] && selected=0 ;; # Down
            esac
        elif [[ $key == "" ]]; then
            break
        fi
        
        printf '\033[5A'
        
        echo -e "Select the mirrors you want to test and apply:\033[K"
        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                echo -e " -> \033[7m ${options[$i]} \033[0m\033[K"
            else
                echo -e "    ${options[$i]}\033[K"
            fi
        done
        echo -e "(Use Up/Down arrows and Enter to select)\033[K"
    done
    echo ""
    return $selected
}

cachyos_main() {
    local version="$1"
    local pretty_name="$2"
    
    if [ -z "$version" ]; then
        version="rolling"
    fi
    
    echo "=== CachyOS Mirror Updater ==="
    echo "Distribution: $pretty_name (Version: $version)"
    echo ""
    check_curl || return 1
    
    cachyos_show_menu
    local choice=$?
    
    echo ""
    
    case $choice in
        0)
            echo "Running CachyOS mirror selection..."
            process_cachyos_mirrors
            ;;
        1)
            echo "Running Arch Linux mirror selection..."
            process_arch_mirrors
            ;;
        2)
            echo "Running Both mirror selections..."
            process_cachyos_mirrors
            echo ""
            echo "========================================="
            echo ""
            process_arch_mirrors
            ;;
    esac
    
    echo ""
    echo "Run 'sudo pacman -Syyu' to sync databases."
}

export -f cachyos_main