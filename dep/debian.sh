#!/bin/bash

check_curl() {
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required." >&2; return 1; }
}

get_debian_mirrors() {
    echo "Fetching Debian mirror list..." >&2
    
    local mirror_list=$(curl -s "https://www.debian.org/mirror/list-full" | \
        grep -Eo 'https?://[^/]+/debian/?' | sort -u)
    
    if [ -z "$mirror_list" ]; then
        echo "WARN: Parsing list-full failed. Falling back to mirrors.debian.org..." >&2
        mirror_list=$(curl -s "https://mirrors.debian.org/mirrors.txt" 2>/dev/null)
    fi
    
    echo "$mirror_list" | sed 's#/*$##' | sed 's#$#/#'
}

find_fastest_mirrors() {
    local count="${1:-5}"
    local suite="$2"
    local mirrors=$(get_debian_mirrors)
    
    if [ -z "$mirrors" ]; then
        echo "ERROR: No mirrors found." >&2
        return 1
    fi
    
    local total=$(echo "$mirrors" | wc -l)
    echo "Testing $total mirrors for suite '$suite' (this may take a few seconds)..." >&2
    
    export suite
    
    echo "$mirrors" | \
        xargs -P 10 -I {} bash -c '
            url="$1"
            time=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 2 --max-time 5 "${url}dists/${suite}/Release" 2>/dev/null)
            if [ -n "$time" ] && [ "$time" != "0.000" ]; then
                echo "$time $url"
            fi
        ' _ {} | \
        sort -n | \
        head -n "$count"
}

debian_main() {
    local version="$1"
    local pretty_name="$2"
    local new_mirror_file="/etc/apt/sources.list.d/debian.sources"
    local old_mirror_file="/etc/apt/sources.list"
    
    local suite="$VERSION_CODENAME"
    if [ -z "$suite" ]; then
        suite="stable"
    fi

    echo "=== Debian Mirror Updater ==="
    echo "Distribution: $pretty_name (Version: $version, Codename: $suite)"
    echo ""
    
    check_curl || return 1
    
    local target_file=""
    if [ -f "$new_mirror_file" ]; then
        target_file="$new_mirror_file"
        echo "Using new DEB822 format: $target_file"
    elif [ -f "$old_mirror_file" ]; then
        target_file="$old_mirror_file"
        echo "Using old format: $target_file"
    else
        echo "ERROR: No sources file found!" >&2
        return 1
    fi
    
    local fastest=$(find_fastest_mirrors 5 "$suite")
    
    if [ -z "$fastest" ]; then
        echo "ERROR: No valid mirrors responded." >&2
        return 1
    fi
    
    echo ""
    echo "=== Fastest mirrors found ==="
    echo "$fastest" | awk '{print $2, "("$1"s)"}' | nl
    echo ""
    
    local sample_mirror=$(echo "$fastest" | head -1 | awk '{print $2}')
    echo "Fastest mirror: $sample_mirror"
    echo ""
    
    echo "Do you want to apply this mirror to your system? (y/n)"
    read -r answer
    
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        echo "Creating backup: ${target_file}.backup"
        sudo cp "$target_file" "${target_file}.backup"
        
        if [[ "$target_file" == *"debian.sources"* ]]; then
            sudo tee "$target_file" > /dev/null << EOF
Types: deb
URIs: $sample_mirror
Suites: $suite $suite-updates $suite-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

EOF
            if [ "$suite" != "sid" ] && [ "$suite" != "testing" ]; then
                sudo tee -a "$target_file" > /dev/null << EOF
Types: deb
URIs: http://security.debian.org/debian-security
Suites: $suite-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

EOF
            fi
        else
            sudo tee "$target_file" > /dev/null << EOF
deb $sample_mirror $suite main contrib non-free non-free-firmware
deb $sample_mirror $suite-updates main contrib non-free non-free-firmware
deb $sample_mirror $suite-backports main contrib non-free non-free-firmware
EOF
            if [ "$suite" != "sid" ] && [ "$suite" != "testing" ]; then
                sudo tee -a "$target_file" > /dev/null << EOF
deb http://security.debian.org/debian-security $suite-security main contrib non-free non-free-firmware
EOF
            fi
        fi
        
        echo "SUCCESS: $target_file updated with the fastest mirror."
        echo "Backup: ${target_file}.backup"
        echo "Run 'sudo apt update' to sync databases."
    else
        local tmp_file="/tmp/debian_mirrorlist.txt"
        echo "# Fastest Debian Mirrors - $(date)" > "$tmp_file"
        echo "$fastest" | awk '{print $2}' >> "$tmp_file"
        echo ""
        echo "Mirror list saved to: $tmp_file"
    fi
}

export -f debian_main