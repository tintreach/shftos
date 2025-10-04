#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  SHTF-OS / EmComm Builder for Linux Mint 22.x (Ubuntu Noble Base)
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
#    This script automates setup of a full emergency communications (EmComm)
#    and amateur radio operating environment on Linux Mint 22.x XFCE, built
#    atop the Ubuntu 24.04 “Noble Numbat” base.
#
#    Components include:
#      • SDR applications (SDR++, GQRX, SDRTrunk, etc.)
#      • Digital comms suites (Fldigi, WSJT-X, JS8Call, FreeDV, Pat, Direwolf)
#      • Signal decoders (DSD-FME, OP25, multimon-ng)
#      • Satellite & AIS tools (Gpredict, SatDump, AIS-Catcher)
#      • GPS/NTP sync and post-install system hygiene utilities
#
#  Credits:
#      Concept, architecture, and integration: Aaron Lamb (KV9L)
#      Special thanks to the open-source maintainers of:
#        • boatbod/op25
#        • lwvmobile/dsd-fme
#        • luarvique/openwebrx-plus
#        • wsjtx / js8call / fldigi / pat / direwolf
#        • SatDump, SDR++, GQRX, and other related contributors
#
#  License:
#      Released under the MIT License
#      © 2025 Aaron Lamb (KV9L). All rights reserved.
#
#  Disclaimer:
#      This script is provided *as-is*, with no warranty of any kind.
#      Use at your own risk. While every effort has been made to prevent
#      damage, misconfiguration, or data loss, the author assumes no
#      responsibility for any harm to hardware, software, or systems
#      resulting from its use. Field-test safely and verify before deployment.
#
#  Notes:
#      • Designed for Linux Mint 22.x XFCE (Ubuntu 24.04 “Noble Numbat” base)
#      • Should also operate on Ubuntu 24.04 desktop with minimal adjustment
#      • Run as a normal user — *not* as root; sudo privileges required
# ════════════════════════════════════════════════════════════════════════════

# --- Pre-flight intro & sudo warm-up (place at very top) ----------------------
pf_info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
pf_warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
pf_error() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

clear
cat <<'BANNER'
┌──────────────────────────────────────────────────────────────────────┐
│                   SHTF EmComm Build (Mint 22.x XFCE)                 │
├──────────────────────────────────────────────────────────────────────┤
│ This will:                                                           │
│  • Install/compile radio apps (SDR, digital modes, decoders, utils)  │
│  • Add trusted upstream repos (with pinning)                         │
│  • Create desktop entries/AppImages where needed                     │
│  • Write a full logfile under ~/shtf-logs/                           │
│                                                                      │
│ Requirements:                                                        │
│  • Internet connection                                               │
│  • ~6–12 GB free disk space (varies with options you choose)         │
│  • Admin privileges (we’ll ask for your sudo password once)          │
└──────────────────────────────────────────────────────────────────────┘
BANNER

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  pf_info "Detected: ${NAME:-Unknown} ${VERSION:-} (${UBUNTU_CODENAME:-?})"
fi

pf_info "You’ll be prompted throughout to opt-in to optional components."
pf_info "We’ll cache your sudo credentials so you won’t be asked again mid-run."
echo

read -r -p "Proceed with the build? [Y/n]: " _pf_go
_pf_go=${_pf_go:-Y}
if [[ ! "$_pf_go" =~ ^[Yy]$ ]]; then
  pf_warn "User aborted before starting."
  exit 0
fi

# --- Log Directory Check ---
LOG_DIR="$HOME/shtf-logs"
if [[ -d "$LOG_DIR" ]]; then
  pf_info "Log directory exists: $LOG_DIR"
else
  pf_info "Creating log directory: $LOG_DIR"
  if mkdir -p "$LOG_DIR"; then
    pf_info "Log directory created successfully."
  else
    pf_error "Failed to create log directory at $LOG_DIR"
    exit 1
  fi
fi

# Create log file and begin capturing output
LOG_FILE="${LOG_DIR}/ham_$(date +%Y%m%d_%H%M%S)_preflight.log"
pf_info "Logging to $LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Sudo warm-up & keepalive ---
pf_info "Preparing privileged operations..."
pf_info "If prompted, enter your password to authorize package installs."
if ! sudo -v; then
  pf_error "Unable to obtain sudo credentials. Exiting."
  exit 1
fi

# Keep sudo alive
( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done ) 2>/dev/null &
_PF_SUDO_KEEPALIVE_PID=$!
trap 'kill -9 ${_PF_SUDO_KEEPALIVE_PID} 2>/dev/null || true' EXIT

pf_info "Pre-flight checks complete. Continuing..."
# --- End pre-flight intro -----------------------------------------------------

# -------- APT/DPKG Safety Net & Preflight --------
export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}
APT_ARGS=${APT_ARGS:-"-y -o Dpkg::Options::=--force-confnew -o Dpkg::Use-Pty=0"}

repair_dpkg() {
  sudo dpkg --configure -a || true
  sudo apt-get -f install -y || true
}

ensure_kernel_build_bits() {
  local krel
  krel="$(uname -r)"
  sudo apt-get update -y
  sudo apt-get install ${APT_ARGS} dkms build-essential linux-headers-"$krel"
}

# Avoid broken xtrx-dkms pulls from Recommends
block_xtrx() {
  sudo mkdir -p /etc/apt/preferences.d
  echo -e "Package: xtrx-dkms\nPin: release *\nPin-Priority: -1" | sudo tee /etc/apt/preferences.d/00-block-xtrx-dkms >/dev/null
}

# Helper: apt install without recommends for known-problem packages
apt_install_nr() {
  sudo apt-get install ${APT_ARGS} --no-install-recommends "$@"
}

# Call once up front
block_xtrx
repair_dpkg
ensure_kernel_build_bits
# SHTF-OS: HAM + SDR + EmComm Complete Installer (Linux Mint 22.2 / Ubuntu 24.04 "Noble")
# - Comprehensive EmComm/SHTF station setup
# - Prints a BOM up front
# - Pauses before each major block and tells you what's next
# - Logs everything to ~/shtf-logs/ham_<timestamp>.log
# - Lets you choose APT vs Flatpak for CHIRP
# - Fixes SDRTrunk download (uses GitHub API; falls back to v0.6.1 exact filename)
#
# Apps/Features:
#   * Drivers: rtl-sdr (+udev rules, DVB blacklist), optional SoapySDR modules
#   * Core ham apps: fldigi, flrig, flmsg, flamp, grig, xdemorse
#   * CHIRP (apt 'chirp' or 'chirp-next' OR Flatpak 'io.github.chirp_next.ChirpNext')
#   * SDR++ (nightly .deb for Ubuntu Noble)
#   * HAMRS (AppImage w/ desktop entry)
#   * SDRTrunk (download, unzip, desktop entry; bundled JRE)
#   * EmComm Suite: pat, JS8Call, Direwolf, WSJT-X, Xastir, APRS tools
#   * Utilities: gqrx, GPredict, multimon-ng, gpsd, readsb/dump1090
#   * Situational Awareness: rtl_433, QSSTV, CQRLog, GridTracker
#   * Network: ax25-tools, socat, chrony
#   * Scanning/Decode: DSD-FME, op25, ais utilities
#   * Optional: SatDump, FreeDV
#
# NOTE: This script assumes an amd64 machine. It will also handle aarch64 for SDRTrunk if detected.
#       You can re-run safely; idempotent steps are guarded.
set -Eeuo pipefail

# -------- Colors --------
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# -------- Logging --------
LOG_DIR="${HOME}/shtf-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/ham_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# -------- Helpers --------
info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){  echo -e "${RED}[ERROR]${NC} $*"; }
pause_next(){
  echo -e "\n${YELLOW}Next:${NC} ${BOLD}$*${NC}"
  read -r -p "Press ENTER to continue (or Ctrl+C to abort) ... "
}

require_nonroot(){
  if [[ ${EUID} -eq 0 ]]; then
    err "Please do NOT run as root. The script will ask for sudo when needed."
    exit 1
  fi
}
apt_install_if_available(){
  local pkg="$1"
  if apt-cache policy "$pkg" | grep -q "Candidate: (none)"; then
    warn "Skipping '$pkg' (not available in your repositories)."
    return 1
  else
    sudo apt-get install -y "$pkg"
  fi
}
ensure_apt_updated(){
  if [[ ! -f /tmp/.shtfos_apt_updated ]]; then
    info "Updating APT package lists ..."
    sudo apt-get update -y
    touch /tmp/.shtfos_apt_updated
  fi
}

detect_arch(){
  local u=$(uname -m)
  case "$u" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "x86_64" ;; # fallback
  esac
}

# -------- BOM --------
ARCH=$(detect_arch)
BOM=$(cat <<'__BOM__'
• Drivers & tooling
  - rtl-sdr (RTL2832U), udev rules, DVB driver blacklist
  - Optional: SoapySDR core + Soapy RTL module (for apps that use Soapy)
  - usbutils
• Core ham radio apps (APT)
  - fldigi, flrig, flmsg, flamp
  - grig (hamlib GUI), xdemorse (CW decoder)
  - Optional: SatDump (if available)
• Programming & logging
  - CHIRP via APT (chirp/chirp-next) OR Flatpak io.github.chirp_next.ChirpNext
  - HAMRS AppImage + desktop entry
• SDR apps
  - SDR++ nightly .deb (Ubuntu Noble build)
  - SDRTrunk (bundled JRE; zip extracted; desktop entry + /usr/local/bin shim)
  - GQRX (quick SDR receiver GUI)
  - Optional: OpenWebRX (web-based SDR server)
• EmComm Digital Modes
  - pat (Winlink CLI client)
  - JS8Call (AppImage) - slow digital mode for EmComm
  - WSJT-X (FT8/FT4/WSPR weak-signal modes)
  - Optional: FreeDV (HF digital voice)
• APRS / Packet Radio
  - Direwolf (software TNC for AX.25/APRS)
  - ax25-tools, ax25-apps (AX.25 stack utilities)
  - multimon-ng (multi-mode digital decoder)
• Satellite Tracking
  - GPredict (satellite tracking and prediction)
• Utilities & Decoders
  - gpsd + gpsd-clients (GPS daemon for APRS/timing)
  - readsb (ADS-B decoder, replaces dump1090-fa)
  - rtl_433 (weather station & sensor decoder)
  - sox, socat (audio/data piping utilities)
  - QSSTV (slow-scan TV)
  - GridTracker (WSJT-X companion for alerts/spotting)
• Network & System
  - chrony (NTP time sync - critical for digital modes)
  - snd-aloop kernel module (virtual audio cables)
  - tunctl, bridge-utils (virtual networking)
• Optional Advanced Tools
  - op25 (P25 trunking decoder)
  - DSD-FME (digital speech decoder)
  - AIS utilities (marine traffic decoding)
  - UPower / acpi (power monitoring for portable ops)
__BOM__
)

clear || true
echo -e "${BOLD}SHTF-OS HAM + SDR + EmComm Complete Installer${NC}"
echo -e "Arch detected: ${BOLD}${ARCH}${NC}"
echo -e "\n${BOLD}Bill of Materials (BOM):${NC}\n${BOM}\n"
echo -e "A detailed log will be written to: ${BOLD}${LOG_FILE}${NC}"
echo

# -------- Start --------
require_nonroot
pause_next "Prep system, make sure curl/wget/flatpak exist"

ensure_apt_updated
sudo apt-get install -y curl wget ca-certificates flatpak unzip git build-essential || true
# Enable Flathub if desired later
if ! flatpak remote-list | grep -q flathub; then
  warn "Flathub not found; adding it (optional, only used if you select Flatpak for CHIRP)."
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
fi

# -------- Drivers: rtl-sdr & udev --------
pause_next "Install RTL-SDR drivers + udev rules and blacklist DVB kernel modules"
ensure_apt_updated
apt_install_if_available librtlsdr2 || true
apt_install_if_available rtl-sdr || true
apt_install_if_available usbutils || true

# Blacklist conflicting DVB kernel modules (if not already blacklisted)
BLACKLIST_FILE="/etc/modprobe.d/blacklist-rtl2832.conf"
if [[ ! -f "$BLACKLIST_FILE" ]]; then
  info "Creating DVB blacklist at ${BLACKLIST_FILE}"
  echo -e "blacklist dvb_usb_rtl28xxu\nblacklist rtl2832\nblacklist rtl2830" | sudo tee "$BLACKLIST_FILE" >/dev/null
  sudo update-initramfs -u || true
fi
sudo udevadm control --reload-rules || true
sudo udevadm trigger || true

# Optional: SoapySDR stack (many SDR apps benefit)
pause_next "OPTIONAL: Install SoapySDR core + RTL module (recommended)."
read -r -p "Install SoapySDR components? [Y/n]: " soapy
soapy=${soapy:-Y}
if [[ "$soapy" =~ ^[Yy]$ ]]; then
  ensure_apt_updated
  apt_install_if_available soapysdr-module-rtlsdr || true
  apt_install_if_available soapysdr0.8-module-rtlsdr || true
  apt_install_if_available soapyremote-server || true
fi

# -------- Core Ham Apps --------
pause_next "Install core ham apps: fldigi, flrig, flmsg, flamp, grig, xdemorse"
ensure_apt_updated
apt_install_if_available fldigi || true
apt_install_if_available flrig || true
apt_install_if_available flmsg || true
apt_install_if_available flamp || true
apt_install_if_available grig || true
apt_install_if_available xdemorse || true

# -------- OPTIONAL: SatDump (.deb from upstream) --------
pause_next "OPTIONAL: Install SatDump (.deb – no compiling)"
read -r -p "Install SatDump via .deb? [y/N]: " do_satdump_deb
do_satdump_deb=${do_satdump_deb:-N}
if [[ "$do_satdump_deb" =~ ^[Yy]$ ]]; then
  # Defaults (override with SATDUMP_VER / SATDUMP_DEB_URL if needed)
  SATDUMP_VER="${SATDUMP_VER:-1.2.2}"
  # Mint 22.2 is Ubuntu 24.04-based; use that artifact
  SATDUMP_DEB_URL="${SATDUMP_DEB_URL:-https://github.com/SatDump/SatDump/releases/download/${SATDUMP_VER}/satdump_${SATDUMP_VER}_ubuntu_24.04_amd64.deb}"

  # Skip if already installed at this version
  if dpkg -s satdump >/dev/null 2>&1; then
    CURV="$(dpkg-query -W -f='${Version}\n' satdump 2>/dev/null || true)"
    if [[ -n "$CURV" ]]; then
      info "SatDump already installed (version: ${CURV})."
      read -r -p "Reinstall/upgrade to ${SATDUMP_VER}? [y/N]: " satdump_reinstall
      satdump_reinstall=${satdump_reinstall:-N}
      if [[ ! "$satdump_reinstall" =~ ^[Yy]$ ]]; then
        info "Keeping existing SatDump. Skipping."
        return 0 2>/dev/null || exit 0
      fi
    fi
  fi

  repair_dpkg
  ensure_apt_updated || sudo apt-get update -y || true

  tmpdeb="$(mktemp /tmp/satdump_${SATDUMP_VER}_XXXX.deb)"
  info "Downloading SatDump ${SATDUMP_VER} (.deb) ..."
  if curl -fsSL --retry 3 --connect-timeout 15 -o "$tmpdeb" -L "$SATDUMP_DEB_URL"; then
    # Install using absolute path from /tmp to avoid the _apt sandbox warning
    if sudo apt-get install ${APT_ARGS} "$tmpdeb"; then
      info "SatDump installed successfully."
    else
      warn "Initial install failed; attempting repair..."
      repair_dpkg
      sudo apt-get -f install -y || true
      sudo apt-get install ${APT_ARGS} "$tmpdeb" || warn "SatDump install may have failed; check logs."
    fi
    rm -f "$tmpdeb"
    # Quick smoke test
    if command -v satdump >/dev/null 2>&1; then
      info "satdump binary present: $(command -v satdump)"
    fi
    if command -v satdump-gui >/div/null 2>&1; then
      info "satdump-gui binary present: $(command -v satdump-gui)"
    fi
  else
    warn "Download failed from: $SATDUMP_DEB_URL"
    warn "Set SATDUMP_DEB_URL to a working link (or SATDUMP_VER) and re-run."
  fi
fi

# -------- CHIRP (APT vs Flatpak) --------
pause_next "Choose CHIRP install method (APT or Flatpak)"
echo "1) APT (tries 'chirp' then 'chirp-next')"
echo "2) Flatpak (io.github.chirp_next.ChirpNext)"
read -r -p "Select [1/2]: " chirp_choice
chirp_choice=${chirp_choice:-1}

if [[ "$chirp_choice" == "2" ]]; then
  info "Installing CHIRP via Flatpak ..."
  flatpak install -y flathub io.github.chirp_next.ChirpNext || warn "Flatpak CHIRP failed."
else
  info "Installing CHIRP via APT ..."
  ensure_apt_updated
  if ! apt_install_if_available chirp; then
    apt_install_if_available chirp-next || warn "Neither 'chirp' nor 'chirp-next' available via APT."
  fi
fi

# -------- HAMRS (AppImage) --------
pause_next "Install HAMRS (AppImage) + desktop entry"
APPDIR="${HOME}/Applications"; DESKTOP_DIR="${HOME}/.local/share/applications"; ICON_DIR="${HOME}/.local/share/icons"
mkdir -p "$APPDIR" "$DESKTOP_DIR" "$ICON_DIR"
HAMRS_URL="https://hamrs-dist.s3.amazonaws.com/hamrs-pro-2.44.0-linux-x86_64.AppImage"
HAMRS_APP="${APPDIR}/hamrs.AppImage"
HAMRS_ICON="${ICON_DIR}/hamrs.png"
HAMRS_ICON_URL="https://play-lh.googleusercontent.com/Z-dK8LkBwx_P5MULcKpDTtunAlikr_kCmDWb7JIPb7h6oCesjxcOCTtlBYcrCBs8LD8=w240-h480-rw"
HAMRS_DESKTOP="${DESKTOP_DIR}/hamrs.desktop"

if [[ ! -f "$HAMRS_APP" ]]; then
  info "Downloading HAMRS AppImage ..."
  curl -L "$HAMRS_URL" -o "$HAMRS_APP"
  chmod +x "$HAMRS_APP"
  if ! "$HAMRS_APP" --appimage-version >/dev/null 2>&1; then
    warn "HAMRS failed to run — installing libfuse2 ..."
    ensure_apt_updated
    sudo apt-get install -y libfuse2 || true
  fi
  curl -L "$HAMRS_ICON_URL" -o "$HAMRS_ICON" || true
  cat > "$HAMRS_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=HAMRS
Comment=HAMRS portable ham radio logging
Exec="${HAMRS_APP}" %U
Icon=${HAMRS_ICON}
Terminal=false
Categories=HamRadio;Utility;Network;
StartupWMClass=hamrs
EOF
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
else
  info "HAMRS already present at ${HAMRS_APP}"
fi

# -------- SDR++ (nightly .deb for Noble) --------
pause_next "Install SDR++ nightly (.deb)"
TMP="/tmp/sdrpp_install"
mkdir -p "$TMP"
SDRPP_DEB="${TMP}/sdrpp_ubuntu_noble_amd64.deb"
SDRPP_URL="https://github.com/AlexandreRouma/SDRPlusPlus/releases/download/nightly/sdrpp_ubuntu_noble_amd64.deb"

if ! command -v sdrpp >/dev/null 2>&1; then
  info "Downloading SDR++ ..."
  wget -O "$SDRPP_DEB" "$SDRPP_URL"
  info "Installing SDR++ (will prompt for sudo) ..."
  sudo apt-get install -y "$SDRPP_DEB" || { sudo apt-get -y --fix-broken install && sudo apt-get install -y "$SDRPP_DEB"; }
else
  info "SDR++ already installed."
fi

# -------- GQRX (quick SDR GUI) --------
pause_next "Install GQRX (simple SDR receiver GUI)"
ensure_apt_updated
apt_install_if_available gqrx-sdr || true

# -------- SDRTrunk (bundled JRE) --------
pause_next "Install SDRTrunk (download, unzip, desktop entry, /usr/local/bin shim)"
SDRTRUNK_BASE="${HOME}/Applications"
SDRTRUNK_DIR="${SDRTRUNK_BASE}/sdrtrunk"
mkdir -p "$SDRTRUNK_BASE"
ARCH_TAG="$(detect_arch)"
get_sdrtrunk_url(){
  local arch="$1"
  local api="https://api.github.com/repos/DSheirer/sdrtrunk/releases/latest"
  local url
  url="$(curl -s "$api" | grep -Eo "https://[^\"]*sdr-trunk-linux-${arch}-v[0-9.]+\.zip" | head -n1)"
  if [[ -z "$url" ]]; then
    url="https://github.com/DSheirer/sdrtrunk/releases/download/v0.6.1/sdr-trunk-linux-${arch}-v0.6.1.zip"
  fi
  echo "$url"
}

SDRTRUNK_URL="$(get_sdrtrunk_url "$ARCH_TAG")"
info "SDRTrunk download URL resolved to: $SDRTRUNK_URL"
SDRTRUNK_ZIP="/tmp/sdrtrunk.zip"

if [[ ! -d "$SDRTRUNK_DIR" ]] || [[ ! -f "${SDRTRUNK_DIR}/bin/sdr-trunk" ]]; then
  wget -O "$SDRTRUNK_ZIP" "$SDRTRUNK_URL"

  unzip -o "$SDRTRUNK_ZIP" -d "$SDRTRUNK_BASE" >/dev/null
  EXTRACTED="$(find "$SDRTRUNK_BASE" -maxdepth 1 -type d -name 'sdr-trunk-*' | sort | tail -n1 || true)"
  if [[ -z "$EXTRACTED" ]]; then
    err "Could not locate extracted sdr-trunk directory."
    exit 1
  fi
  rm -rf "$SDRTRUNK_DIR"
  mv "$EXTRACTED" "$SDRTRUNK_DIR"
else
  info "SDRTrunk already installed at ${SDRTRUNK_DIR}"
fi

SDRTRUNK_DESKTOP="${DESKTOP_DIR}/sdrtrunk.desktop"
cat > "$SDRTRUNK_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=SDRTrunk
Comment=Trunked radio decoding and monitoring
Exec=${SDRTRUNK_DIR}/bin/sdr-trunk
Icon=${SDRTRUNK_DIR}/lib/sdrtrunk.png
Terminal=false
Categories=Network;AudioVideo;HamRadio;
EOF
update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true

# CLI shim
if [[ ! -f /usr/local/bin/sdrtrunk ]]; then
  info "Creating /usr/local/bin/sdrtrunk launcher ..."
  echo '#!/usr/bin/env bash' | sudo tee /usr/local/bin/sdrtrunk >/dev/null
  echo "exec \"${SDRTRUNK_DIR}/bin/sdr-trunk\" \"\$@\"" | sudo tee -a /usr/local/bin/sdrtrunk >/dev/null
  sudo chmod +x /usr/local/bin/sdrtrunk
else
  info "SDRTrunk launcher already exists at /usr/local/bin/sdrtrunk"
fi

info "SDRTrunk installed successfully at ${SDRTRUNK_DIR}"
info "Launch with: sdrtrunk (or from application menu)"

# -------- EmComm: pat (Winlink) --------
pause_next "Install pat (Winlink CLI client)"
PAT_VERSION="0.15.1"
PAT_DEB="/tmp/pat_${PAT_VERSION}_linux_amd64.deb"
PAT_URL="https://github.com/la5nta/pat/releases/download/v${PAT_VERSION}/pat_${PAT_VERSION}_linux_amd64.deb"

if ! command -v pat >/dev/null 2>&1; then
  info "Downloading pat ${PAT_VERSION} ..."
  wget -O "$PAT_DEB" "$PAT_URL"
  sudo apt-get install -y "$PAT_DEB" || true
else
  info "pat already installed."
fi

# -------- EmComm: JS8Call (.deb or AppImage) --------
pause_next "Install JS8Call (.deb or AppImage for slow digital EmComm)"

# Defaults (overridable)
JS8_VER="${JS8_VER:-2.2.0}"
JS8_DEB_URL="${JS8_DEB_URL:-http://files.js8call.com/${JS8_VER}/js8call_${JS8_VER}_20.04_amd64.deb}"
JS8_APPIMG_URL="${JS8_APPIMG_URL:-http://files.js8call.com/${JS8_VER}/js8call-${JS8_VER}-Linux-Desktop.x86_64.AppImage}"

# Install locations
JS8_APPDIR="/opt/js8call"
JS8_APP="${JS8_APPDIR}/JS8Call.AppImage"
JS8_DESKTOP_SYS="/usr/share/applications/js8call.desktop"

read -r -p "Install JS8Call? [y/N]: " js8
js8=${js8:-N}
if [[ "$js8" =~ ^[Yy]$ ]]; then
  echo "Choose JS8Call source:"
  echo "  1) .deb (APT-managed; integrates cleanly)"
  echo "  2) AppImage (portable under ${JS8_APPDIR})"
  echo "  3) Skip"
  read -r -p "Selection [1/2/3]: " js8_sel
  js8_sel=${js8_sel:-1}

  repair_dpkg

  case "$js8_sel" in
    1)
      info "Installing JS8Call via .deb ..."
      tmpdeb="$(mktemp /tmp/js8call_XXXX.deb)"
      if curl -fsSL --retry 3 --connect-timeout 10 "$JS8_DEB_URL" -o "$tmpdeb"; then
        sudo apt-get install ${APT_ARGS} "$tmpdeb" \
          || { repair_dpkg; sudo apt-get install ${APT_ARGS} "$tmpdeb" || true; }
        rm -f "$tmpdeb"
        repair_dpkg
        info "JS8Call (.deb) installed."
      else
        warn "Download failed from $JS8_DEB_URL"
        warn "Set JS8_DEB_URL to a working link and re-run."
      fi
      ;;
    2)
      info "Installing JS8Call AppImage ..."
      tmpapp="$(mktemp /tmp/js8call_XXXX.AppImage)"
      if curl -fsSL --retry 3 --connect-timeout 10 "$JS8_APPIMG_URL" -o "$tmpapp"; then
        sudo install -d "${JS8_APPDIR}"
        sudo install -m 0755 "$tmpapp" "${JS8_APP}"
        rm -f "$tmpapp"
        sudo tee "${JS8_DESKTOP_SYS}" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=JS8Call
Comment=Slow digital mode for EmComm
Exec=${JS8_APP}
Icon=audio-card
Terminal=false
Categories=HamRadio;Network;
EOF
        command -v update-desktop-database >/dev/null 2>&1 \
          && update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
        info "JS8Call (AppImage) installed to ${JS8_APP}."
      else
        warn "Download failed from $JS8_APPIMG_URL"
        warn "Set JS8_APPIMG_URL to a working link and re-run."
      fi
      ;;
    *)
      info "Skipping JS8Call."
      ;;
  esac
fi

# -------- EmComm: WSJT-X --------
pause_next "Install WSJT-X (FT8/FT4/WSPR weak-signal modes)"
ensure_apt_updated
apt_install_if_available wsjtx || true

# -------- EmComm: Direwolf (Software TNC) --------
pause_next "Install Direwolf (AX.25/APRS software TNC)"
ensure_apt_updated
apt_install_if_available direwolf || true

# -------- EmComm: AX.25 Tools --------
pause_next "Install AX.25 packet radio stack (ax25-tools, ax25-apps)"
ensure_apt_updated
apt_install_if_available ax25-tools || true
apt_install_if_available ax25-apps || true
apt_install_if_available libax25 || true

# -------- Utilities: multimon-ng, sox, socat --------
pause_next "Install audio/data utilities (multimon-ng, sox, socat)"
ensure_apt_updated
apt_install_if_available multimon-ng || true
apt_install_if_available sox || true
apt_install_if_available socat || true

# Load snd-aloop for virtual audio cables
if ! lsmod | grep -q snd_aloop; then
  info "Loading snd-aloop kernel module ..."
  sudo modprobe snd-aloop || warn "Could not load snd-aloop module."
  echo "snd-aloop" | sudo tee -a /etc/modules >/dev/null || true
fi

# -------- GPS: gpsd --------
pause_next "Install gpsd + gpsd-clients (GPS daemon for APRS/timing)"
ensure_apt_updated
apt_install_if_available gpsd || true
apt_install_if_available gpsd-clients || true

# -------- ADS-B: readsb or dump1090-fa --------
pause_next "Install ADS-B decoder (readsb preferred, dump1090-fa fallback)"
ensure_apt_updated
# readsb isn't in Ubuntu repos, try dump1090-fa
if ! apt_install_if_available readsb; then
  info "readsb not available, trying dump1090-fa..."
  apt_install_if_available dump1090-fa || warn "No ADS-B decoder available in repos. Install manually if needed."
fi

# -------- Weather/Sensors: rtl_433 --------
pause_next "Install rtl_433 (decode weather stations & 433MHz sensors)"
ensure_apt_updated
apt_install_if_available rtl-433 || true

# -------- Satellite: GPredict --------
pause_next "Install GPredict (satellite tracking and prediction)"
ensure_apt_updated
apt_install_if_available gpredict || true

# -------- SSTV: QSSTV --------
pause_next "Install QSSTV (slow-scan TV image transmission)"
ensure_apt_updated
apt_install_if_available qsstv || true

# -------- OPTIONAL: GridTracker --------
# --- OPTIONAL: Install GridTracker (WSJT-X companion) ---
echo "|Next: OPTIONAL: Install GridTracker (WSJT-X spotting/alerting companion)"
read -r -p "Press ENTER to continue (or Ctrl+C to abort) ..." _
echo
read -r -p "Install GridTracker? [y/N]: " gt
gt=${gt:-N}
if [[ "$gt" =~ ^[Yy]$ ]]; then
  # Let user choose source
  echo "Choose GridTracker source:"
  echo "  1) .deb (managed by APT; prefers system integration)"
  echo "  2) Flatpak (sandboxed; auto-updates via flatpak)"
  echo "  3) Skip"
  read -r -p "Selection [1/2/3]: " gt_sel
  gt_sel=${gt_sel:-1}

  repair_dpkg

  # Allow version override via env; defaults to pinned version for reproducibility
  GT_VERSION="${GT_VERSION:-2.250914.1}"
  GT_DEB_URL="${GT_DEB_URL:-https://download2.gridtracker.org/GridTracker2-${GT_VERSION}-amd64.deb}"
  GT_APPIMG_URL="${GT_APPIMG_URL:-https://download2.gridtracker.org/GridTracker2-${GT_VERSION}-x86_64.AppImage}"

  case "$gt_sel" in
    1)
      echo "Installing GridTracker via .deb ..."
      tmpdeb="$(mktemp -u /tmp/gridtracker_XXXX.deb)"
      if curl -L --fail --retry 3 --max-time 120 "$GT_DEB_URL" -o "$tmpdeb"; then
        sudo apt-get install ${APT_ARGS} "$tmpdeb" || { repair_dpkg; sudo apt-get install ${APT_ARGS} "$tmpdeb" || true; }
        rm -f "$tmpdeb"
      else
        echo "Download failed from $GT_DEB_URL"
        echo "You can set GT_DEB_URL env var to a different link and re-run."
      fi
      repair_dpkg
      ;;
    2)
      echo "Installing GridTracker via Flatpak ..."
      # Ensure flatpak and Flathub
      sudo apt-get update -y
      sudo apt-get install ${APT_ARGS} flatpak || true
      if ! flatpak remote-list | grep -qi flathub; then
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
      fi
      # No official flathub package as of writing; fallback to appimage under /opt with desktop file.
      echo "GridTracker is not officially on Flathub; we'll install the AppImage to /opt/gridtracker and integrate."
      tmpapp="$(mktemp -u /tmp/gridtracker_XXXX.AppImage)"
      if curl -L --fail --retry 3 --max-time 120 "$GT_APPIMG_URL" -o "$tmpapp"; then
        sudo install -d /opt/gridtracker
        sudo install -m 0755 "$tmpapp" /opt/gridtracker/GridTracker.AppImage
        rm -f "$tmpapp"
        # Integrate with desktop
        sudo tee /usr/share/applications/gridtracker.desktop >/dev/null <<'EOF'
[Desktop Entry]
Name=GridTracker
Exec=/opt/gridtracker/GridTracker.AppImage
Terminal=false
Type=Application
Icon=gridtracker
Categories=HamRadio;Network;Utility;
EOF
        # Try to fetch icon if present in AppImage at runtime (optional)
        # Users can override GT_APPIMG_URL to a newer build later.
      else
        echo "Download failed from $GT_APPIMG_URL"
        echo "You can set GT_APPIMG_URL env var to a different link and re-run."
      fi
      ;;
    *)
      echo "Skipping GridTracker."
      ;;
  esac
fi
# -------- Network: chrony (NTP sync) --------
pause_next "Install chrony (NTP time sync - critical for digital modes)"
ensure_apt_updated
apt_install_if_available chrony || true
sudo systemctl enable chrony || true
sudo systemctl start chrony || true

# -------- Network: tunctl, bridge-utils --------
pause_next "Install network utilities (tunctl, bridge-utils for virtual networking)"
ensure_apt_updated
apt_install_if_available uml-utilities || true  # provides tunctl
apt_install_if_available bridge-utils || true

# -------- OPTIONAL: FreeDV --------
pause_next "OPTIONAL: Install FreeDV (HF digital voice)"
read -r -p "Install FreeDV? [y/N]: " freedv
freedv=${freedv:-N}
if [[ "$freedv" =~ ^[Yy]$ ]]; then
  ensure_apt_updated
  apt_install_if_available freedv || true
fi

# -------- OPTIONAL: op25 (build from source) --------
pause_next "OPTIONAL: Install op25 (P25 trunking decoder - build from source)"

read -r -p "Install op25? [y/N]: " do_op25
do_op25=${do_op25:-N}
if [[ "$do_op25" =~ ^[Yy]$ ]]; then
  echo
  echo "op25 build note:"
  echo "• This will download sources, install a *large* set of -dev dependencies,"
  echo "  and compile multiple C++/Python modules."
  echo "• On modest hardware or slow disks, this can take quite a while."
  read -r -p "Proceed with op25 build? [y/N]: " op25_go
  op25_go=${op25_go:-N}
  if [[ "$op25_go" =~ ^[Yy]$ ]]; then
    info "Cloning op25 repository ..."
    mkdir -p "$HOME/src"
    if [[ ! -d "$HOME/src/op25" ]]; then
      git clone https://github.com/boatbod/op25.git "$HOME/src/op25"
    fi
    info "Installing op25 dependencies ..."
    sudo apt-get update
    sudo apt-get install ${APT_ARGS} \
      git g++ python3-dev python3-numpy gnuradio-dev gr-osmosdr \
      cmake libitpp-dev libpcap-dev libhackrf-dev librtlsdr-dev \
      libusb-1.0-0-dev libdbus-1-dev \
      libboost-all-dev python3-pip python3-wheel || { repair_dpkg; sudo apt-get -f install -y || true; }

    info "Building and installing op25 (this can take a while) ..."
    pushd "$HOME/src/op25" >/dev/null
    mkdir -p build && cd build
    cmake ..
    make -j"$(nproc)"
    sudo make install
    sudo ldconfig
    popd >/dev/null
    echo "op25 installed."
  else
    info "Skipping op25 build."
  fi
fi

# -------- OPTIONAL: DSD-FME (digital speech decoder - DMR/P25/NXDN) --------
pause_next "OPTIONAL: Install DSD-FME (digital speech decoder - DMR/P25/NXDN)"
read -r -p "Install DSD-FME? [y/N]: " dsd
dsd=${dsd:-N}
if [[ "$dsd" =~ ^[Yy]$ ]]; then
  DSD_DIR="${HOME}/src/dsd-fme"
  MBE_BUILT=0

  info "Installing dependencies for DSD-FME ..."
  ensure_apt_updated
  sudo apt-get install -y \
    git build-essential cmake pkg-config \
    libsndfile1-dev libportaudio2 portaudio19-dev \
    libasound2-dev libpulse-dev libncurses-dev

  # --- Check for libmbe-dev, build from source if unavailable ---
  if ! dpkg -s libmbe-dev >/dev/null 2>&1; then
    info "Attempting to install libmbe-dev from repository ..."
    if ! sudo apt-get install -y libmbe-dev; then
      warn "libmbe-dev not found in repositories; building mbelib from source ..."
      mkdir -p "${HOME}/src"
      if [[ ! -d "${HOME}/src/mbelib" ]]; then
        git clone https://github.com/szechyjs/mbelib.git "${HOME}/src/mbelib"
      fi
      pushd "${HOME}/src/mbelib" >/dev/null
      mkdir -p build && cd build
      cmake -DCMAKE_BUILD_TYPE=Release ..
      make -j"$(nproc)"
      sudo make install
      sudo ldconfig
      popd >/dev/null
      MBE_BUILT=1
    fi
  fi

  # --- Clone or update DSD-FME repository ---
  mkdir -p "${HOME}/src"
  if [[ ! -d "$DSD_DIR" ]]; then
    info "Cloning DSD-FME repository ..."
    git clone https://github.com/lwvmobile/dsd-fme.git "$DSD_DIR"
  else
    info "Updating existing DSD-FME repository ..."
    git -C "$DSD_DIR" pull --ff-only || true
  fi

  # --- Build and install DSD-FME ---
  pushd "$DSD_DIR" >/dev/null
  rm -rf build && mkdir build && cd build
  cmake -DCMAKE_BUILD_TYPE=Release ..
  make -j"$(nproc)"
  sudo make install
  sudo ldconfig
  popd >/dev/null

  if command -v dsd-fme >/dev/null 2>&1; then
    echo "DSD-FME installed successfully!"
    echo
    echo "Run with:  dsd-fme --help"
    if [[ "$MBE_BUILT" -eq 1 ]]; then
      info "Note: mbelib was built from source (no package available)."
    fi
  else
    warn "DSD-FME binary not found. Check build output for errors."
  fi
else
  info "Skipping DSD-FME installation."
fi


## -------- OPTIONAL: AIS utilities (marine vessel tracking) --------
pause_next "OPTIONAL: Install AIS utilities (rtl-ais from APT; optional ais-catcher from source)"
read -r -p "Install AIS tools? [y/N]: " do_ais
do_ais=${do_ais:-N}

if [[ "$do_ais" =~ ^[Yy]$ ]]; then
  ensure_apt_updated
  info "Installing rtl-ais (APT) ..."
  if apt_install_if_available rtl-ais; then
    # Quiet help probe (handle builds that don't support --help)
    if ! rtl_ais --help >/dev/null 2>&1; then
      rtl_ais 2>&1 | head -n 8 || true
    fi
    echo "rtl-ais installed."
  else
    warn "rtl-ais not found in your repos. You can try: sudo apt-get install rtl-ais"
  fi

  echo
  read -r -p "Also build ais-catcher from source? [y/N]: " do_ac
  do_ac=${do_ac:-N}
  if [[ "$do_ac" =~ ^[Yy]$ ]]; then
    info "Installing build dependencies for ais-catcher ..."
    sudo apt-get install -y ${APT_ARGS:-} git cmake g++ make \
      libfftw3-dev libusb-1.0-0-dev librtlsdr-dev || { repair_dpkg; sudo apt-get -f install -y || true; }

    AC_DIR="${HOME}/src/ais-catcher"
    mkdir -p "${HOME}/src"

    if [[ ! -d "$AC_DIR" ]]; then
      info "Cloning ais-catcher (shallow) ..."
      git clone --depth=1 https://github.com/jvde-github/ais-catcher.git "$AC_DIR"
    else
      info "Updating existing ais-catcher repo ..."
      (cd "$AC_DIR" && git pull --ff-only || true)
    fi

    info "Building ais-catcher ..."
    pushd "$AC_DIR" >/dev/null
    mkdir -p build && cd build
    cmake -DCMAKE_BUILD_TYPE=Release ..
    make -j"$(nproc)"

    # Handle binary name casing from the generator
    if [[ -f "./AIS-catcher" ]]; then
      BIN="./AIS-catcher"
    elif [[ -f "./ais-catcher" ]]; then
      BIN="./ais-catcher"
    else
      warn "ais-catcher binary not found after build:"
      ls -la .
      popd >/dev/null
      return 0
    fi

    sudo install -m 0755 "$BIN" /usr/local/bin/ais-catcher
    popd >/dev/null

    # Quiet help check
    if ! ais-catcher --help >/dev/null 2>&1; then
      ais-catcher 2>&1 | head -n 8 || true
    fi
    echo "ais-catcher installed to /usr/local/bin/ais-catcher."
  else
    info "Skipping ais-catcher build."
  fi
fi


# -------- OPTIONAL: Repeater-START (repeater control utility) --------
pause_next "OPTIONAL: Install Repeater-START (repeater control and monitoring utility)"
read -r -p "Install Repeater-START? [y/N]: " repeater_start
repeater_start=${repeater_start:-N}
if [[ "$repeater_start" =~ ^[Yy]$ ]]; then
  info "Downloading Repeater-START package ..."
  RSTART_URL="https://sourceforge.net/projects/repeater-start/files/repeater-start_1.0.3_all.deb/download"
  TMPDEB="$(mktemp -u /tmp/repeater-start_XXXX.deb)"

  if curl -fL --retry 3 --connect-timeout 10 -o "$TMPDEB" "$RSTART_URL"; then
    info "Installing Repeater-START (.deb) ..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get install -y "$TMPDEB" \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confnew" || {
        warn "Install encountered issues, attempting repair ..."
        sudo dpkg --configure -a || true
        sudo apt-get -f install -y || true
        sudo apt-get install -y "$TMPDEB" \
          -o Dpkg::Options::="--force-confdef" \
          -o Dpkg::Options::="--force-confnew" || true
      }

    rm -f "$TMPDEB"
    update-desktop-database >/dev/null 2>&1 || true
    update-mime-database /usr/share/mime >/dev/null 2>&1 || true

    if dpkg -s repeater-start >/dev/null 2>&1; then
      echo "Repeater-START installed successfully."
      echo "Launch via menu or run: repeater-start"
    else
      warn "Repeater-START did not register properly; check APT output."
    fi
  else
    warn "Failed to download Repeater-START from SourceForge."
  fi
else
  info "Skipping Repeater-START installation."
fi

# -------- Power Management --------
pause_next "Install power management utilities (UPower, acpi for portable ops)"
ensure_apt_updated
apt_install_if_available upower || true
apt_install_if_available acpi || true
apt_install_if_available powertop || true

# -------- Reference Materials Setup --------
pause_next "OPTIONAL: Download offline reference materials (frequency charts, band plans)"
read -r -p "Download ham radio reference PDFs? [y/N]: " refs
refs=${refs:-N}
if [[ "$refs" =~ ^[Yy]$ ]]; then
  REF_DIR="${HOME}/Documents/HamRadio-Reference"
  mkdir -p "$REF_DIR"
  info "Creating reference directory at ${REF_DIR}"
  info "You can manually add ARRL band plans, frequency charts, and antenna guides here."
  echo "Reference directory created at: ${REF_DIR}" > "${REF_DIR}/README.txt"
fi

# -------- Offline Map Cache Setup --------
pause_next "OPTIONAL: Setup for offline map caching (for Xastir/GPredict)"
read -r -p "Create offline map cache directory structure? [y/N]: " maps
maps=${maps:-N}
if [[ "$maps" =~ ^[Yy]$ ]]; then
  MAP_DIR="${HOME}/.xastir/maps"
  mkdir -p "$MAP_DIR"
  info "Map cache directory created at ${MAP_DIR}"
  info "You can download OpenStreetMap tiles using tools like 'osm-tiles' or Xastir's built-in map downloader."
fi

# -------- Post checks --------
pause_next "Quick driver sanity check (rtl_test -s 1024000 for 5 seconds)"
if command -v rtl_test >/dev/null 2>&1; then
  timeout 5 rtl_test -s 1024000 || warn "rtl_test returned a non-zero status (device might be unplugged)."
else
  warn "rtl_test not found (rtl-sdr may not have installed)."
fi

# -------- Final cleanup (safe) --------
# Controls:
#   DO_CLEAN=yes|no      -> run cleanup (default: yes)
#   VACUUM_JOURNAL=7d    -> systemd journal retention (blank to skip)
#   EXTRA_PURGE=""       -> add extra packages to purge (space-separated)

DO_CLEAN="${DO_CLEAN:-yes}"
VACUUM_JOURNAL="${VACUUM_JOURNAL:-3d}"
EXTRA_PURGE="${EXTRA_PURGE:-}"

if [[ "$DO_CLEAN" == "yes" ]]; then
  info "Starting final cleanup…"
  before="$(df -h / | awk 'NR==2{print $4}')"

  # Make sure package db is sane first
  repair_dpkg

  # Optional: purge anything explicitly requested by caller (e.g., editors/tools you tried temporarily)
  if [[ -n "$EXTRA_PURGE" ]]; then
    info "Purging extra packages: $EXTRA_PURGE"
    sudo apt-get purge -y $EXTRA_PURGE || true
    repair_dpkg
  fi

  # Remove automatically-installed packages no longer needed
  sudo apt-get autoremove -y --purge || true
  repair_dpkg

  # Trim APT caches (keeps package lists intact)
  sudo apt-get autoclean -y || true
  sudo apt-get clean -y || true

  # Sweep our temp artifacts (from .deb/AppImage downloads)
  sudo rm -f /tmp/js8call_*.deb /tmp/js8call_*.AppImage /tmp/gridtracker_*.deb /tmp/*.AppImage 2>/dev/null || true
  sudo rm -f /tmp/*.deb /tmp/*.tar.* /tmp/*.zip 2>/dev/null || true

  # Optional: shrink systemd journal to keep the image lean
  if [[ -n "$VACUUM_JOURNAL" ]] && command -v journalctl >/dev/null 2>&1; then
    sudo journalctl --vacuum-time="$VACUUM_JOURNAL" || true
  fi

  # Clear pip cache if we used pip (skip if you want reproducible offline reinstalls)
  if command -v pip3 >/dev/null 2>&1; then
    pip3 cache purge >/dev/null 2>&1 || true
  fi

  # Final sweep of orphaned config files
  sudo dpkg -l | awk '/^rc/ {print $2}' | xargs -r sudo dpkg --purge >/dev/null 2>&1 || true

  after="$(df -h / | awk 'NR==2{print $4}')"
  info "Cleanup complete. Free space: was ${before}, now ${after}."
else
  info "Skipping final cleanup (DO_CLEAN=${DO_CLEAN})."
fi

echo
info "All done. Log saved to: ${LOG_FILE}"
echo -e "\n${BOLD}=== Installation Summary ===${NC}\n"
echo -e "${BLUE}Core SDR/Scanning:${NC}"
echo "  sdrpp | sdrtrunk | gqrx | rtl_test | rtl_433"
echo -e "${BLUE}Digital Modes:${NC}"
echo "  fldigi | flrig | flmsg | flamp | wsjtx | js8call | freedv"
echo -e "${BLUE}EmComm/Winlink:${NC}"
echo "  pat | direwolf"
echo -e "${BLUE}Logging:${NC}"
echo "  hamrs (${HAMRS_APP})"
echo -e "${BLUE}Programming:${NC}"
echo "  chirp (or flatpak run io.github.chirp_next.ChirpNext)"
echo -e "${BLUE}Satellite:${NC}"
echo "  gpredict | satdump (if installed)"
echo -e "${BLUE}Utilities:${NC}"
echo "  grig | xdemorse | qsstv | multimon-ng | gpsd"
echo -e "${BLUE}Decoders:${NC}"
echo "  readsb (ADS-B) | rtl_433 (weather/sensors) | op25 (P25) | dsd-fme (DMR/P25/NXDN)"
echo
echo -e "${YELLOW}Post-Install Recommendations:${NC}"
echo "  1. **Fix broken package (xtrx-dkms):** Run 'sudo dpkg --remove --force-remove-reinstreq xtrx-dkms' if you see dpkg errors"
echo "  2. Reboot to ensure kernel modules (snd-aloop, rtl-sdr) load properly"
echo "  3. Configure Direwolf: edit ~/.config/direwolf/direwolf.conf"
echo "  4. Configure pat: run 'pat configure' and set your Winlink credentials"
echo "  5. Test GPS: run 'cgps' or 'gpsmon' to verify gpsd connectivity"
echo "  6. Add yourself to 'dialout' group for radio/TNC access: sudo usermod -aG dialout \$USER"
echo "  7. Download offline maps to ${HOME}/.local/share/maps"
echo "  8. Time sync check: run 'chronyc tracking' to verify NTP sync"
echo "  9. For AX.25 networking, configure /etc/ax25/ after reboot"
echo " 10. Set up virtual audio cables (snd-aloop) for digital mode audio routing"
echo
echo -e "${GREEN}[SUCCESS]${NC} EmComm station setup complete!"
echo -e "Documentation and logs: ${LOG_FILE}"
