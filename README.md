# 🚀 Sort-Mirrors

A powerful, lightweight, and interactive Bash script designed to automatically find, test, and apply the fastest package mirrors for **Arch Linux**, **Ubuntu**, **Debian**, and **CachyOS** based on your network's real-time latency.

Tired of slow package downloads? This script fetches official mirror lists, parses them securely, tests their response times concurrently, and safely applies the fastest one to your system.

## ✨ Features

- **Multi-Distro Support:** Now natively supports Arch, Ubuntu, Debian, and CachyOS.
- **Auto-Detection:** Automatically detects your Linux distribution, version, and architecture (including `x86_64-v3` for CachyOS).
- **Parallel Testing:** Tests multiple mirrors concurrently using `xargs` to save time.
- **Broad Compatibility:**
  - Supports both legacy (`sources.list`) and modern DEB822 (`.sources`) formats for Ubuntu/Debian.
  - Auto-detects CPU architecture (`x86_64`, `aarch64`, etc.) for Arch-based systems.
- **Safe & Secure:** Always creates a `.backup` of your original mirror configuration files before making any changes.
- **Robust Fallbacks:** If HTML parsing of mirror lists fails (e.g., due to gzip/binary formats), the script automatically falls back to raw text lists or official main mirrors to ensure it never fails.
- **Clean Output:** Properly redirects status messages to `stderr`, ensuring variables remain clean and uncorrupted.
- **Zero Dependencies:** Only requires `bash` and `curl` (which are pre-installed on almost all Linux systems).

## 📦 Supported Distributions

Currently, the script fully supports the following distributions out of the box:

| Distribution   | Mirror Source                          | Target File                              |
| :------------- | :------------------------------------- | :--------------------------------------- |
| **Arch Linux** | `archlinux.org/mirrorlist/all/`        | `/etc/pacman.d/mirrorlist`               |
| **CachyOS**    | `packages.cachyos.org/mirrors`         | `/etc/pacman.d/cachyos-mirrorlist`       |
| **Ubuntu**     | `launchpad.net/ubuntu/+archivemirrors` | `/etc/apt/sources.list.d/ubuntu.sources` |
| **Debian**     | `debian.org/mirror/list-full`          | `/etc/apt/sources.list.d/debian.sources` |

_Note: Popular derivatives like Linux Mint, Pop!\_OS, and Manjaro are automatically mapped to their base distributions._

## 📥 Installation & Usage

You don't need to install anything! Just clone the repository and run the script.

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/sort-mirrors.git
cd sort-mirrors
```

### 2. Make the script executable

```bash
chmod +x sort-mirrors.sh
```

### 3. Run the script

```bash
./sort-mirrors.sh
```

The script will guide you through the process, show you the top 5 fastest mirrors, and ask for your confirmation before applying the changes.

## 🛠️ How It Works

1. **Identify:** Reads `/etc/os-release` to determine your OS, version, and codename.
2. **Fetch:** Downloads the official mirror list from the respective distribution's website (handling gzip/compressed responses).
3. **Parse:** Extracts valid HTTP/HTTPS URLs using `grep` and `sed`, filtering out static assets (like CSS/SVG) and internal dashboard links.
4. **Test:** Uses `curl` to download a tiny test file (like `Release` or `core.db`) from each mirror securely, measuring the `time_total`.
5. **Sort:** Sorts the mirrors based on their response time in ascending order.
6. **Apply:** Safely backs up your current configuration and writes the fastest mirror to the system package manager config.

## 🔮 Roadmap (Future Development)

We are actively working on expanding the script to natively support popular derivatives with dedicated optimizations and native mirror lists.

**Planned for upcoming releases:**

- [ ] **Manjaro Linux:** Dedicated support for `pacman-mirrors` API.
- [ ] **Linux Mint:** Native Linux Mint mirror list integration.
- [ ] **Pop!\_OS:** Dedicated Pop!\_OS repository mirroring.
- [ ] **Kali Linux:** Native Kali rolling repository mirrors.
- [ ] Add `--yes` or `-y` flag for non-interactive/automated deployments.
- [ ] Add progress spinner during mirror testing.

## ⚠️ Disclaimer

This script modifies critical system files (`/etc/apt/sources.list`, `/etc/pacman.d/mirrorlist`, etc.). Although it creates a `.backup` of your original files, please use it with caution. Ensure you have stable internet connectivity while running the script.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page if you want to contribute.
