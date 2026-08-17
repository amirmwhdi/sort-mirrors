#!/bin/bash

check_curl() {
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required." >&2; return 1; }
}

get_ubuntu_mirrors() {
    echo "Fetching Ubuntu mirror list from launchpad.net..." >&2
    
    local mirror_list=$(curl -s -A "Mozilla/5.0" "https://launchpad.net/ubuntu/+archivemirrors" | \
        grep -Eo 'href="https?://[^"]+ubuntu/?"' | \
        sed 's/href="//;s/"$//' | \
        sed 's#/*$##' | \
        sed 's#$#/#' | \
        sort -u)
    
    if [ -z "$mirror_list" ]; then
        echo "WARN: Launchpad parsing failed. Falling back to mirrors.ubuntu.com..." >&2
        mirror_list=$(curl -s "https://mirrors.ubuntu.com/mirrors.txt" 2>/dev/null | sed 's#/*$##' | sed 's#$#/#')
    fi
    
    echo "$mirror_list"
}

find_fastest_mirrors() {
    local count="${1:-5}"
    local codename="$2"
    local mirrors=$(get_ubuntu_mirrors)
    
    if [ -z "$mirrors" ]; then
        echo "ERROR: No mirrors found. Check your internet connection." >&2
        return 1
    fi
    
    local total=$(echo "$mirrors" | wc -l)
    echo "Testing $total mirrors for $codename (this may take a few seconds)..." >&2
    
    export codename
    
    echo "$mirrors" | \
        xargs -P 10 -I {} bash -c '
            url="{}"
            time=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 2 --max-time 5 "${url}dists/${codename}/Release" 2>/dev/null)
            if [ -n "$time" ] && [ "$time" != "0.000" ]; then
                echo "$time $url"
            fi
        ' | \
        sort -n | \
        head -n "$count"
}

ubuntu_main() {
    local version="$1"
    local pretty_name="$2"
    local codename="$VERSION_CODENAME"
    local mirror_file="/etc/apt/sources.list.d/ubuntu.sources"
    local old_file="/etc/apt/sources.list"
    
    if [ -z "$codename" ]; then
        codename=$(lsb_release -cs 2>/dev/null || echo "focal")
    fi
    
    echo "=== Ubuntu Mirror Updater ==="
    echo "Distribution: $pretty_name (Version: $version, Codename: $codename)"
    echo ""
    
    check_curl || return 1
    
    local target_file=""
    if [ -f "$mirror_file" ]; then
        target_file="$mirror_file"
        echo "Using new DEB822 format: $target_file"
    elif [ -f "$old_file" ]; then
        target_file="$old_file"
        echo "Using old format: $old_file"
    else
        echo "ERROR: No sources file found!"
        return 1
    fi
    
    local fastest=$(find_fastest_mirrors 5 "$codename")
    
    if [ -z "$fastest" ]; then
        echo "ERROR: No mirrors responded."
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
        
        if [[ "$target_file" == *"ubuntu.sources"* ]]; then
            sudo tee "$target_file" > /dev/null << EOF
Types: deb
URIs: $sample_mirror
Suites: $codename $codename-updates $codename-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: $codename-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
        else
            sudo tee "$target_file" > /dev/null << EOF
deb $sample_mirror $codename main restricted universe multiverse
deb $sample_mirror $codename-updates main restricted universe multiverse
deb $sample_mirror $codename-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $codename-security main restricted universe multiverse
EOF
        fi
        
        echo "SUCCESS: $target_file updated with the fastest mirror."
        echo "Backup: ${target_file}.backup"
        echo "Run 'sudo apt update' to sync databases."
    else
        local tmp_file="/tmp/ubuntu_mirrorlist.txt"
        echo "# Fastest Ubuntu Mirrors - $(date)" > "$tmp_file"
        echo "$fastest" | awk '{print $2}' >> "$tmp_file"
        echo ""
        echo "Mirror list saved to: $tmp_file"
    fi
}

export -f ubuntu_main