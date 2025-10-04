#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  SHTF-OS / EmComm Utilities Installer (Linux Mint 22.x / Ubuntu 24.04)
# ════════════════════════════════════════════════════════════════════════════
#  Version: 1.0.0 (Release Candidate)
#  Build Date: $(date +'%Y-%m-%d')
#
#  Author: Aaron Lamb (KV9L)
#  Contact: aaron@kv9l.com
#  Website: https://kv9l.com
#
#  Project: SHTF-OS — Self-Contained Ham / EmComm Linux Environment
#
#  Description:
#    Installs non-radio “support” utilities for an EmComm workstation:
#    offline knowledge, mapping, file sync, crypto, media tools, services,
#    and shell utilities. Safe to re-run; idempotent steps are guarded.
#
#  Credits:
#    Concept & integration: Aaron Lamb (KV9L)
#    Thanks to the maintainers of the listed upstream packages.
#
#  License:
#    MIT License — © 2025 Aaron Lamb (KV9L)
#
#  Disclaimer:
#    Provided “AS IS”, without warranty of any kind. You assume all risk.
#    Verify on a snapshot first and review changes before deployment.
# ════════════════════════════════════════════════════════════════════════════

set -Eeuo pipefail

# -------- APT/DPKG safety net (mirrors RC1 style) ---------------------------
export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}
APT_ARGS=${APT_ARGS:-"-y -o Dpkg::Options::=--force-confnew -o Dpkg::Use-Pty=0"}

repair_dpkg() {
  sudo dpkg --configure -a || true
  sudo apt-get -f install -y || true
}

# -------- Colors -------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# -------- Logging (make dir if absent) --------------------------------------
LOG_DIR="${HOME}/shtf-logs"
if [[ ! -d "$LOG_DIR" ]]; then
  mkdir -p "$LOG_DIR"
fi
LOG_FILE="${LOG_DIR}/shtfutils_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# -------- Helpers ------------------------------------------------------------
info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){  echo -e "${RED}[ERROR]${NC} $*"; }
pause_next(){
  echo -e "\n${YELLOW}Next:${NC} ${BOLD}$*${NC}"
  read -r -p "Press ENTER to continue (or Ctrl+C to abort) ... "
}
require_nonroot(){
  if [[ ${EUID} -eq 0 ]]; then
    err "Please run as your normal user. We'll ask for sudo when needed."
    exit 1
  fi
}
apt_install_if_available(){
  local pkg="$1"
  if apt-cache policy "$pkg" | grep -q "Candidate: (none)"; then
    warn "Skipping '$pkg' (not available in your repositories)."
    return 1
  else
    sudo apt-get install ${APT_ARGS} "$pkg"
  fi
}
ensure_apt_updated(){
  if [[ ! -f /tmp/.shtfutils_apt_updated ]]; then
    info "Updating APT package lists ..."
    sudo apt-get update -y
    touch /tmp/.shtfutils_apt_updated
  fi
}
detect_arch(){
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "x86_64" ;; # fallback
  esac
}

# -------- Preflight banner & sudo warm-up -----------------------------------
clear
cat <<'BANNER'
┌──────────────────────────────────────────────────────────────────────┐
│                SHTF-OS Utilities Installer (Mint 22.x)               │
├──────────────────────────────────────────────────────────────────────┤
│ This will:                                                           │
│  • Install offline knowledge, mapping, crypto, media & sys tools     │
│  • Create helpful directories (offline maps, references, ebooks)     │
│  • Log everything under ~/shtf-logs/                                 │
│                                                                      │
│ Requirements:                                                        │
│  • Internet connection                                               │
│  • A few GB free disk space                                          │
│  • Admin privileges (sudo)                                           │
└──────────────────────────────────────────────────────────────────────┘
BANNER

# Warm up sudo (ask once), with a friendly explanation
echo -e "${BLUE}We’ll cache sudo now so you aren’t prompted repeatedly.${NC}"
sudo -v || { err "sudo authorization failed."; exit 1; }
# Keep sudo fresh during long runs
( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done ) 2>/dev/null &

# -------- BOM ---------------------------------------------------------------
ARCH=$(detect_arch)
BOM=$(cat <<'__BOM__'
• Offline Knowledge & Docs
  - Kiwix (offline Wikipedia & wikis), Calibre, FBReader, Foliate, Zeal
• Communication (non-radio)
  - Mumble (voice), irssi/weechat (IRC), optional: signal-cli
• Mapping & Navigation
  - QGIS, gpxsee, Marble (offline map viewer)
• File Sync & Backup
  - Syncthing, rsync, duplicity
• Security & Encryption
  - GnuPG, KeePassXC, VeraCrypt
• Media & Imaging
  - FFmpeg, ImageMagick, Audacity
• Lightweight Services
  - lighttpd, dnsmasq, sshfs
• Weather / Satellites
  - wxtoimg*, predict  (*often community/3rd-party packaged)
• Terminal & System
  - tmux, screen, vim/nano, htop, iotop, ncdu, jq
• Network Diagnostics (optional)
  - nmap, tcpdump, Wireshark (prompted)
__BOM__
)

echo -e "Arch detected: ${BOLD}${ARCH}${NC}"
echo -e "\n${BOLD}Bill of Materials (BOM):${NC}\n${BOM}\n"
echo -e "Log file: ${BOLD}${LOG_FILE}${NC}\n"

# -------- Start --------------------------------------------------------------
require_nonroot
pause_next "Prep system (curl/wget/https) and repair any partial dpkg state"

repair_dpkg
ensure_apt_updated
sudo apt-get install ${APT_ARGS} curl wget ca-certificates apt-transport-https gnupg >/dev/null || true

# ===== Offline Knowledge: Kiwix =============================================
pause_next "Install Kiwix (offline Wikipedia & knowledge) — AppImage under ~/Applications"
KIWIX_APPIMAGE="${HOME}/Applications/kiwix.AppImage"
KIWIX_URL="https://download.kiwix.org/release/kiwix-desktop/kiwix-desktop_x86_64.appimage"
DESKTOP_DIR="${HOME}/.local/share/applications"
mkdir -p "${HOME}/Applications" "$DESKTOP_DIR"

if [[ ! -f "$KIWIX_APPIMAGE" ]]; then
  info "Downloading Kiwix AppImage ..."
  curl -L "$KIWIX_URL" -o "$KIWIX_APPIMAGE"
  chmod +x "$KIWIX_APPIMAGE"
  # If libfuse2 missing, install it
  if ! "$KIWIX_APPIMAGE" --version >/dev/null 2>&1; then
    warn "Kiwix didn’t run; adding libfuse2 ..."
    ensure_apt_updated
    sudo apt-get install ${APT_ARGS} libfuse2 || true
  fi
  cat > "${DESKTOP_DIR}/kiwix.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kiwix
Comment=Offline knowledge (Wikipedia, Wikibooks, etc.)
Exec=${KIWIX_APPIMAGE} %U
Icon=accessories-dictionary
Terminal=false
Categories=Education;Science;Literature;
EOF
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  info "Kiwix installed. Get .zim files from https://library.kiwix.org/"
else
  info "Kiwix already present."
fi

KIWIX_LIBRARY="${HOME}/Documents/Kiwix-Library"
mkdir -p "$KIWIX_LIBRARY"
info "Kiwix library directory: ${KIWIX_LIBRARY}"

# ===== Ebook management/readers =============================================
pause_next "Install Calibre (ebook manager) and readers (FBReader, Foliate)"
ensure_apt_updated
apt_install_if_available calibre   || true
apt_install_if_available fbreader  || true
apt_install_if_available foliate   || true

# Zeal (offline API/docs)
pause_next "Install Zeal (offline API/documentation browser)"
ensure_apt_updated
apt_install_if_available zeal || true

# ===== Communication (non-radio) ============================================
pause_next "Install Mumble (voice) + IRC clients (irssi/weechat)"
ensure_apt_updated
apt_install_if_available mumble  || true
apt_install_if_available irssi   || true
apt_install_if_available weechat || true
# Optional: signal-cli keeps changing; leave commented unless you wire a working repo
# apt_install_if_available signal-cli || true

# ===== Mapping & Navigation ==================================================
pause_next "Install mapping tools (QGIS, gpxsee, Marble)"
ensure_apt_updated
apt_install_if_available qgis  || true
apt_install_if_available gpxsee || true
apt_install_if_available marble || true

# ===== File Sync & Backup ====================================================
pause_next "Install Syncthing (peer sync) + rsync + duplicity"
ensure_apt_updated
apt_install_if_available syncthing || true
apt_install_if_available rsync     || true
apt_install_if_available duplicity || true

# ===== Security & Encryption ================================================
pause_next "Install GnuPG, KeePassXC, VeraCrypt"
ensure_apt_updated
apt_install_if_available gnupg       || true
apt_install_if_available keepassxc   || true
apt_install_if_available veracrypt   || true

# ===== Media & Imaging =======================================================
pause_next "Install media & imaging tools (FFmpeg, ImageMagick, Audacity)"
ensure_apt_updated
apt_install_if_available ffmpeg        || true
apt_install_if_available imagemagick   || true
apt_install_if_available audacity      || true

# ===== Lightweight Services ==================================================
pause_next "Install light services (lighttpd, dnsmasq, sshfs)"
ensure_apt_updated
apt_install_if_available lighttpd || true
apt_install_if_available dnsmasq  || true
apt_install_if_available sshfs    || true

# ===== Weather / Satellites ==================================================
pause_next "Install predict (satellite tracking CLI) and wxtoimg (if present)"
ensure_apt_updated
apt_install_if_available predict   || true
# wxtoimg may be absent in Noble; keep guarded
apt_install_if_available wxtoimg   || true

# ===== Terminal & System Utilities ==========================================
pause_next "Install terminal/system utilities (tmux, screen, vim/nano, htop, iotop, ncdu, jq)"
ensure_apt_updated
apt_install_if_available tmux  || true
apt_install_if_available screen || true
apt_install_if_available vim   || true
apt_install_if_available nano  || true
apt_install_if_available htop  || true
apt_install_if_available iotop || true
apt_install_if_available ncdu  || true
apt_install_if_available jq    || true

# ===== Network Diagnostics (optional Wireshark) ==============================
pause_next "Install network diagnostics (nmap, tcpdump) — Wireshark is optional"
ensure_apt_updated
apt_install_if_available nmap    || true
apt_install_if_available tcpdump || true
read -r -p "Install Wireshark (packet analyzer)? [y/N]: " wireshark
wireshark=${wireshark:-N}
if [[ "$wireshark" =~ ^[Yy]$ ]]; then
  apt_install_if_available wireshark || true
  info "If you want non-root capture: sudo usermod -aG wireshark $USER (then reboot)"
fi

# ===== Offline Storage & Reference Trees ====================================
pause_next "Create offline storage folders (maps, references, ebooks) & quick templates"

MAPS_DIR="${HOME}/Documents/Offline-Maps"
mkdir -p "$MAPS_DIR"/{osm,marble,gpx}
echo "Store OSM tiles, Marble maps, and GPX tracks here." > "${MAPS_DIR}/README.txt"
info "Offline map storage: ${MAPS_DIR}"

REF_DIR="${HOME}/Documents/SHTF-Reference"
mkdir -p "$REF_DIR"/{medical,survival,technical,legal}
cat > "${REF_DIR}/README.txt" <<'EOF'
SHTF Reference Materials
========================
Store critical offline docs here:
/medical   - First aid, drug info
/survival  - Water, shelter, field craft
/technical - Radio manuals, electronics
/legal     - Local emergency procedures
EOF
info "Reference directory: ${REF_DIR}"

EBOOK_DIR="${HOME}/Documents/Ebook-Library"
mkdir -p "$EBOOK_DIR"
info "Ebook library: ${EBOOK_DIR} (import into Calibre)"

# Quick template
cat > "${REF_DIR}/emergency-contacts.txt" <<'EOF'
EMERGENCY CONTACTS
==================
Last Updated: [DATE]

LOCAL EMERGENCY
- Police/Fire/EMS: 911
- Non-emergency: [LOCAL NUMBER]

HAM RADIO
- Net Control: [CALLSIGN] [FREQ]
- Local Repeaters: [LIST]
- ARES/RACES: [CONTACT]

UTILITIES
- Power:
- Water:
- Gas:

FAMILY / FRIENDS
- [NAME] — [PHONE/EMAIL/RADIO]
EOF

# ===== Wrap-up ===============================================================
pause_next "Final cleanup & summary"
# No autoremove here automatically (you can uncomment if you want the behavior):
# sudo apt-get autoremove -y || true

FREE_BEFORE="$(df -h ~ | awk 'NR==2{print $4}')"
sync
FREE_AFTER="$(df -h ~ | awk 'NR==2{print $4}')"
info "Cleanup done. Free space (home fs): was ${FREE_BEFORE}, now ${FREE_AFTER}."

echo -e "\n${GREEN}[SUCCESS]${NC} Utilities setup complete."
echo "Log saved to: ${LOG_FILE}"
echo
echo "Notes:"
echo " • Kiwix ZIM downloads: https://library.kiwix.org/"
echo " • Consider pre-downloading maps/docs while you have bandwidth."
echo " • Re-run this script safely anytime; it will skip already-done steps."
