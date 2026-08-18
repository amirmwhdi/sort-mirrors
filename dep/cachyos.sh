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
    
    local mirror_files=(
        "/etc/pacman.d/cachyos-mirrorlist"
        "/etc/pacman.d/cachyos-v3-mirrorlist"
        "/etc/pacman.d/cachyos-v4-mirrorlist"
    )
    
    local cachyos_arch="x86_64"
    
    if [ -z "$version" ]; then
        version="rolling"
    fi
    
    echo "=== CachyOS Mirror Updater ==="
    echo "Distribution: $pretty_name (Version: $version)"
    echo "Architecture: $cachyos_arch (testing base)"
    echo ""
    
    check_curl || return 1
    
    local found_file=false
    for f in "${mirror_files[@]}"; do
        if [ -f "$f" ]; then
            found_file=true
            break
        fi
    done
    
    if [ "$found_file" = false ]; then
        echo "ERROR: No CachyOS mirrorlist files found in /etc/pacman.d/!" >&2
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
        
        echo ""
        echo "SUCCESS: CachyOS mirrorlists updated with the fastest mirrors."
        echo "Run 'sudo pacman -Syyu' to sync databases."
    else
        echo "No changes made."
    fi
}

export -f cachyos_main