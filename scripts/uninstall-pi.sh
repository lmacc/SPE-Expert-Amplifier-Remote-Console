#!/usr/bin/env bash
#
# uninstall-pi.sh — one-shot uninstaller for the SPE Expert Amplifier
# Remote daemon installed by install-pi.sh.
#
# Stops the systemd service, removes the unit, the installed binary and
# the install directory. User config + TLS certificates in
# /var/lib/spe-remote/ are PRESERVED by default; pass --purge to remove
# those too.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/lmacc/SPE-Expert-Amplifier-Remote-Console/main/scripts/uninstall-pi.sh | sudo bash
#   sudo bash uninstall-pi.sh                  # safe default — keeps config
#   sudo bash uninstall-pi.sh --purge          # also delete /var/lib/spe-remote
#
# Things deliberately NOT removed:
#   - Runtime Qt 6 libraries — other apps may need them. Run
#       sudo apt remove libqt6httpserver6 libqt6websockets6 libqt6serialport6 \
#                       libqt6network6 libqt6core6
#     by hand if you're sure nothing else uses them.
#   - 'dialout' group membership of the service user — other serial apps
#     (CAT control, rotators) commonly need it.
#
set -euo pipefail

INSTALL_DIR="${SPE_INSTALL_DIR:-/opt/spe-remote}"
SERVICE_DST="/etc/systemd/system/spe-remoted.service"
BIN_LINK="/usr/local/bin/spe-remoted"
STATE_DIR="/var/lib/spe-remote"
PURGE=0

# ------------------------------------------------------------------- #
log()  { printf '\033[36m[uninstall]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[uninstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[uninstall]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (use sudo)."

while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge)   PURGE=1; shift ;;
        -h|--help)
            cat <<EOF
Usage:  sudo bash uninstall-pi.sh [--purge]

  (default)   Stop + remove the service, binary, and install directory.
              Keep persistent config + TLS certs under $STATE_DIR.
  --purge     Also delete $STATE_DIR (config + TLS state).
EOF
            exit 0 ;;
        *)         warn "Ignoring unknown argument: $1"; shift ;;
    esac
done

# ------------------------------------------------------------------- #
# Stop + disable the systemd service if it's around.
# ------------------------------------------------------------------- #
if systemctl list-unit-files spe-remoted.service >/dev/null 2>&1 \
   || [[ -f "$SERVICE_DST" ]]; then
    log "Stopping spe-remoted service …"
    systemctl stop    spe-remoted 2>/dev/null || true
    systemctl disable spe-remoted 2>/dev/null || true
fi

if [[ -f "$SERVICE_DST" ]]; then
    log "Removing $SERVICE_DST"
    rm -f "$SERVICE_DST"
    systemctl daemon-reload
    systemctl reset-failed spe-remoted 2>/dev/null || true
fi

# Drop the USB-serial module-preload the installer added (leaves the modules
# loaded for this session; they're unloaded at the next reboot if unused).
if [[ -f /etc/modules-load.d/spe-remote.conf ]]; then
    log "Removing /etc/modules-load.d/spe-remote.conf"
    rm -f /etc/modules-load.d/spe-remote.conf
fi

# Drop the ModemManager ignore rule for USB-serial adapters.
if [[ -f /etc/udev/rules.d/99-spe-remote-mm.rules ]]; then
    log "Removing /etc/udev/rules.d/99-spe-remote-mm.rules"
    rm -f /etc/udev/rules.d/99-spe-remote-mm.rules
    udevadm control --reload-rules 2>/dev/null || true
fi

# Catch any stray manual processes (e.g. someone ran ./spe-remoted by hand).
if pgrep -x spe-remoted >/dev/null 2>&1; then
    log "Stopping stray spe-remoted process(es) …"
    pkill -TERM -x spe-remoted 2>/dev/null || true
    sleep 1
    pkill -KILL -x spe-remoted 2>/dev/null || true
fi

# ------------------------------------------------------------------- #
# Remove the binary symlink (or a stale plain file at that path).
# ------------------------------------------------------------------- #
if [[ -L "$BIN_LINK" || -e "$BIN_LINK" ]]; then
    log "Removing $BIN_LINK"
    rm -f "$BIN_LINK"
fi

# ------------------------------------------------------------------- #
# Remove the install directory.
# ------------------------------------------------------------------- #
if [[ -d "$INSTALL_DIR" ]]; then
    log "Removing $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
fi

# ------------------------------------------------------------------- #
# Persistent config + TLS state.
# ------------------------------------------------------------------- #
if [[ "$PURGE" == "1" && -d "$STATE_DIR" ]]; then
    log "Purging $STATE_DIR (config + TLS certs) …"
    rm -rf "$STATE_DIR"
elif [[ -d "$STATE_DIR" ]]; then
    warn "Kept $STATE_DIR (config + TLS certs). Pass --purge next time to remove it too."
fi

# ------------------------------------------------------------------- #
echo
ok "SPE Expert Amplifier Remote has been uninstalled."
echo
echo "  Left in place on purpose:"
echo "    - Runtime Qt 6 libraries (other apps may need them)."
echo "    - 'dialout' group membership."
[[ "$PURGE" == "1" ]] || echo "    - $STATE_DIR  (your config + TLS certs)."
