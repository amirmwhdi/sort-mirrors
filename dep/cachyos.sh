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

find_fastest_mirrors() {
    local count="${1:-5}"
    local arch="$2"
    local mirrors=$(get_cachyos_mirrors)
    
    if [ -z "$mirrors" ]; then
        echo "ERROR: No CachyOS mirrors found." >&2
        return 1
    fi
    
    local total=$(echo "$mirrors" | wc -l)
    echo "Testing $total CachyOS mirrors for arch '$arch'..." >&2
    
    echo "$mirrors" | \
        xargs -P 10 -I {} bash -c '
            url="$1"
            time=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 2 --max-time 5 "${url}cachyos/${arch}/cachyos.db" 2>/dev/null)
            if [ -n "$time" ] && [ "$time" != "0.000" ]; then
                echo "$time $url"
            fi
        ' _ {} | \
        sort -n | \
        head -n "$count"
}

cachyos_main() {
    local version="$1"
    local pretty_name="$2"
    local file="/etc/pacman.d/cachyos-mirrorlist"
    
    local cachyos_arch="x86_64"
    
    if [ -z "$version" ]; then
        version="rolling"
    fi
    
    echo "=== CachyOS Mirror Updater ==="
    echo "Distribution: $pretty_name (Version: $version)"
    echo "Architecture: $cachyos_arch (testing base)"
    echo ""
    
    check_curl || return 1
    
    if [ ! -f "$file" ]; then
        echo "ERROR: File $file does not exist!" >&2
        return 1
    fi
    
    local fastest=$(find_fastest_mirrors 5 "$cachyos_arch")
    
    if [ -z "$fastest" ]; then
        echo "ERROR: No CachyOS mirrors responded." >&2
        return 1
    fi
    
    echo ""
    echo "=== Fastest CachyOS mirrors found ==="
    echo "$fastest" | awk '{print $2, "("$1"s)"}' | nl
    echo ""
    
    local best_mirror=$(echo "$fastest" | head -1 | awk '{print $2}')
    echo "Fastest mirror: $best_mirror"
    echo ""
    
    echo "Do you want to backup and replace the CachyOS mirrorlist? (y/n)"
    read -r answer
    
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        echo "Creating backup: ${file}.backup"
        sudo cp "$file" "${file}.backup"
        
        echo "$fastest" | awk '{print "Server = " $2 "$repo/$arch"}' | sudo tee "$file" > /dev/null
        
        echo "SUCCESS: $file updated with fastest CachyOS mirrors."
        echo "Backup: ${file}.backup"
        echo "Run 'sudo pacman -Syyu' to sync databases."
    else
        echo "No changes made."
    fi
}

export -f cachyos_main