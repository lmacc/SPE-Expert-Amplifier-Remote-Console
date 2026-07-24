#!/usr/bin/env bash
#
# install.sh — one-shot installer for the SPE Expert Amplifier Remote
# daemon on a 64-bit Debian/Ubuntu/Raspberry Pi OS box.
#
# Removes any previous SPE Remote install (binaries + systemd unit), keeps
# the user's saved config under /var/lib/spe-remote, and lays down the
# latest release.
#
# Usage:
#   curl -sSL https://github.com/lmacc/SPE-Expert-Amplifier-Remote-Console/releases/latest/download/install.sh | sudo bash
#
#   sudo bash install.sh        # from a local copy
#
# Options (set as environment variables before sudo):
#   SPE_TAG=v1.9.12              Pin to a specific release (default: latest).
#   SPE_USER=mike                Service runs as this user (default: $SUDO_USER or pi).
#   SPE_INSTALL_DIR=/opt/X       Install path (default: /opt/spe-remote).
#   SPE_KEEP_CONFIG=0            Wipe saved config too (default: 1, keep it).
#   SPE_HTTP_PORT=8081           Initial HTTP port (default: 8081 — avoids clash
#                                with TS-890S Webserver default 8080).
#   SPE_WS_PORT=8889             Initial WebSocket port (default: 8889).
#
set -euo pipefail

REPO="lmacc/SPE-Expert-Amplifier-Remote-Console"
TAG="${SPE_TAG:-latest}"
INSTALL_DIR="${SPE_INSTALL_DIR:-/opt/spe-remote}"
STATE_DIR="/var/lib/spe-remote"
SERVICE_DST="/etc/systemd/system/spe-remoted.service"
BIN_LINK="/usr/local/bin/spe-remoted"
TARGET_USER="${SPE_USER:-${SUDO_USER:-pi}}"
KEEP_CONFIG="${SPE_KEEP_CONFIG:-1}"
# Default to 8081/8889 instead of the daemon's compile-time 8080/8888, so a
# fresh install doesn't fight a TS-890S Webserver (8080/8073) running on the
# same Pi. Users can override via env vars or change them later via spe-config.
SPE_HTTP_PORT="${SPE_HTTP_PORT:-8081}"
SPE_WS_PORT="${SPE_WS_PORT:-8889}"

# ------------------------------------------------------------------- #
log()  { printf '\033[36m[install]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[install]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (use sudo)."
id "$TARGET_USER" >/dev/null 2>&1 \
    || die "Target user '$TARGET_USER' does not exist. Set SPE_USER=<name>."

case "$(uname -m)" in
    aarch64|arm64) ARCH="linux-arm64" ;;
    x86_64|amd64)  ARCH="linux-x64"   ;;
    *) die "Unsupported architecture: $(uname -m). Prebuilt binaries cover linux-x64 and linux-arm64 only." ;;
esac
log "Architecture: $ARCH   service user: $TARGET_USER"

# ------------------------------------------------------------------- #
# Remove any previous install BEFORE laying down the new one. The new
# tarball ships its own Qt under lib/, so we want a clean directory —
# leftover .so files from an older install can otherwise shadow newer ones
# at runtime via $ORIGIN/lib.
# ------------------------------------------------------------------- #
log "Looking for an existing install to remove …"

# Stop + disable the primary service if it exists. Don't touch secondary
# instances (spe-remoted-*.service) — those are user-managed via spe-config.
if systemctl list-unit-files spe-remoted.service >/dev/null 2>&1 \
    && systemctl list-unit-files spe-remoted.service | grep -q '^spe-remoted.service'; then
    log "Stopping existing spe-remoted.service …"
    systemctl stop spe-remoted.service 2>/dev/null || true
    systemctl disable spe-remoted.service 2>/dev/null || true
fi

# Wipe the install dir (binaries, libs, plugins, docs) but NOT the state dir
# (config.json, tls/, Let's Encrypt copies). The user's serial port choice,
# amp model, web port, cert paths etc. all live in $STATE_DIR.
if [[ -d "$INSTALL_DIR" ]]; then
    log "Removing old install at $INSTALL_DIR …"
    rm -rf "$INSTALL_DIR"
fi

# Clear the symlink — we recreate it after extracting.
[[ -L "$BIN_LINK" || -e "$BIN_LINK" ]] && rm -f "$BIN_LINK"

# Wipe state too if explicitly requested.
if [[ "$KEEP_CONFIG" != "1" && -d "$STATE_DIR" ]]; then
    warn "SPE_KEEP_CONFIG=0 — wiping saved config at $STATE_DIR"
    rm -rf "$STATE_DIR"
fi

# ------------------------------------------------------------------- #
# Apt prerequisites. The tarball bundles its own Qt + plugins under lib/
# and plugins/, so we don't need system Qt packages.
# ------------------------------------------------------------------- #
log "Installing prerequisites (apt) …"
apt-get update -qq
apt-get install -y --no-install-recommends \
    curl ca-certificates tar \
    >/dev/null

# ------------------------------------------------------------------- #
# Resolve the release and asset URL via the GitHub API. No jq dependency.
# ------------------------------------------------------------------- #
API="https://api.github.com/repos/$REPO/releases/latest"
[[ "$TAG" != "latest" ]] && API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
log "Looking up release: $TAG"
RELEASE_JSON=$(curl -fsSL "$API") \
    || die "Cannot reach GitHub releases API."

NEW_TAG=$(printf '%s' "$RELEASE_JSON" \
            | grep -m1 -E '"tag_name"' \
            | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
[[ -n "$NEW_TAG" ]] || die "Couldn't determine release tag from API."
ok "Latest release: $NEW_TAG"

ASSET_URL=$(printf '%s' "$RELEASE_JSON" \
              | grep -E '"browser_download_url"' \
              | grep -E "${ARCH}\\.tar\\.gz" \
              | head -n1 \
              | sed -E 's/.*"(https:[^"]+)".*/\1/')
[[ -n "$ASSET_URL" ]] || die "No asset matching '${ARCH}' on release $NEW_TAG."
ASSET_NAME="$(basename "$ASSET_URL")"

EXPECTED_SHA=$(printf '%s' "$RELEASE_JSON" \
                 | awk -v name="$ASSET_NAME" '
                     /"name"/ { in_match = ($0 ~ name); }
                     in_match && /"digest"/ {
                         match($0, /sha256:[0-9a-f]+/);
                         if (RSTART) print substr($0, RSTART+7, RLENGTH-7);
                         exit;
                     }')

# ------------------------------------------------------------------- #
# Download → verify → extract.
# ------------------------------------------------------------------- #
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ARCHIVE="$TMP/$ASSET_NAME"

DOWNLOAD_OK=0
for attempt in 1 2 3; do
    log "Downloading $ASSET_NAME (attempt $attempt/3) …"
    rm -f "$ARCHIVE"
    if curl -fsSL \
            -H 'Cache-Control: no-cache, no-store' -H 'Pragma: no-cache' \
            --retry 3 --retry-delay 2 --connect-timeout 30 \
            -o "$ARCHIVE" "$ASSET_URL"; then
        if [[ -z "$EXPECTED_SHA" ]]; then
            warn "Release has no digest field — skipping SHA-256 check."
            DOWNLOAD_OK=1
            break
        fi
        ACTUAL_SHA=$(sha256sum "$ARCHIVE" | awk '{print $1}')
        if [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]]; then
            ok "SHA-256 verified."
            DOWNLOAD_OK=1
            break
        fi
        warn "SHA-256 mismatch on attempt $attempt — download was likely truncated."
    else
        warn "Download failed on attempt $attempt (curl exit code $?)."
    fi
    [[ $attempt -lt 3 ]] && sleep 2
done

[[ "$DOWNLOAD_OK" == "1" ]] \
    || die "Could not get a valid archive after 3 attempts."

log "Extracting to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
tar -xzf "$ARCHIVE" -C "$INSTALL_DIR" --strip-components=1
chown -R "$TARGET_USER":"$TARGET_USER" "$INSTALL_DIR"

ln -sf "$INSTALL_DIR/spe-remoted" "$BIN_LINK"

# Pull the spe-config helper from the SAME release we just installed, so
# script + binary stay in lock-step. Older releases (pre-v1.9.13) don't ship
# this asset; fall back to the main-branch raw URL for those, and don't fail
# the install if it isn't found either way.
CONFIG_URL_VER="https://github.com/$REPO/releases/download/$NEW_TAG/spe-config.sh"
CONFIG_URL_RAW="https://raw.githubusercontent.com/$REPO/main/scripts/spe-config.sh"
if curl -fsSL -o /usr/local/bin/spe-config "$CONFIG_URL_VER" 2>/dev/null \
    || curl -fsSL -o /usr/local/bin/spe-config "$CONFIG_URL_RAW" 2>/dev/null; then
    chmod 0755 /usr/local/bin/spe-config
    ok "Installed spe-config helper → run 'sudo spe-config' to change ports or enable HTTPS."
fi

# ------------------------------------------------------------------- #
# Sanity check: the binary actually starts on this system. Catches Qt-ABI
# / missing-library issues here, with a clear error, instead of via a
# systemd restart loop later.
# ------------------------------------------------------------------- #
log "Verifying the binary runs on this system …"
if ! out=$("$BIN_LINK" --version 2>&1); then
    die "Installed binary failed to run:
$out

This usually means the runtime Qt libraries don't match what the binary
was built against (Qt HttpServer in particular has an unstable ABI across
patch levels). Please report it at:
  https://github.com/$REPO/issues"
fi
ok "Binary runs: $out"

# ------------------------------------------------------------------- #
log "Adding $TARGET_USER to the dialout group (serial access) …"
usermod -a -G dialout "$TARGET_USER" || true

if command -v tailscale >/dev/null 2>&1; then
    log "Setting $TARGET_USER as Tailscale operator (for cert fetch from the web UI) …"
    tailscale set --operator="$TARGET_USER" \
        || warn "tailscale set --operator failed; the cert button in the web UI may need 'sudo tailscale set --operator=$TARGET_USER' run manually."
fi

log "Writing $SERVICE_DST"
cat > "$SERVICE_DST" <<EOF
[Unit]
Description=SPE Expert Amplifier Remote daemon
Documentation=https://github.com/$REPO
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
Group=dialout

Environment=XDG_CONFIG_HOME=/var/lib/spe-remote
StateDirectory=spe-remote

ExecStart=$BIN_LINK
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
# Let the daemon read Let's Encrypt copies (configurable via spe-config).
ReadOnlyPaths=/etc/letsencrypt
# Allow USB-serial (ttyUSB*, char major 188) and USB-CDC (ttyACM*, char major
# 166) devices by device GROUP, not by fixed node path. A DeviceAllow=/dev/...
# path is resolved to a single major:minor at unit-start time, so if the
# adapter isn't plugged in when the service starts — or is replugged as a
# different ttyUSBn — the sandbox denies the port with "Operation not
# permitted" (EPERM) even though the web UI still lists it. The char-ttyUSB /
# char-ttyACM groups cover every such node regardless of plug order or which
# number it enumerates as.
DeviceAllow=char-ttyUSB rw
DeviceAllow=char-ttyACM rw
# On-board GPIO UART (Raspberry Pi) — present from boot, so a node path is fine.
DeviceAllow=/dev/ttyAMA0 rw
DeviceAllow=/dev/serial0 rw

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$SERVICE_DST"

# Register the USB-serial tty cores at boot so the service's device-group
# allow rules (char-ttyUSB / char-ttyACM) always resolve — otherwise a first
# plug-in after a boot-with-nothing-attached fails with "Operation not
# permitted". modprobe now so it also works this session.
log "Registering USB-serial drivers at boot (so the port opens after a replug) …"
cat > /etc/modules-load.d/spe-remote.conf <<'MODULES_EOF'
# USB-serial (ttyUSB*, major 188) and USB-CDC (ttyACM*, major 166) tty cores.
usbserial
cdc_acm
MODULES_EOF
chmod 0644 /etc/modules-load.d/spe-remote.conf
modprobe usbserial 2>/dev/null || true
modprobe cdc_acm 2>/dev/null || true

# ModemManager probes new serial ports as possible modems and can hold the
# port ("Device or resource busy"). Tag the common USB-serial bridges so it
# ignores them. Harmless if ModemManager isn't installed.
log "Installing ModemManager ignore rule for USB-serial adapters …"
cat > /etc/udev/rules.d/99-spe-remote-mm.rules <<'MM_EOF'
# Keep ModemManager off SPE USB-serial adapters (FTDI, CP210x, CH340, PL2303).
ACTION=="add|change", SUBSYSTEM=="tty", SUBSYSTEMS=="usb", ATTRS{idVendor}=="0403", ENV{ID_MM_DEVICE_IGNORE}="1"
ACTION=="add|change", SUBSYSTEM=="tty", SUBSYSTEMS=="usb", ATTRS{idVendor}=="10c4", ENV{ID_MM_DEVICE_IGNORE}="1"
ACTION=="add|change", SUBSYSTEM=="tty", SUBSYSTEMS=="usb", ATTRS{idVendor}=="1a86", ENV{ID_MM_DEVICE_IGNORE}="1"
ACTION=="add|change", SUBSYSTEM=="tty", SUBSYSTEMS=="usb", ATTRS{idVendor}=="067b", ENV{ID_MM_DEVICE_IGNORE}="1"
# USB-CDC amps (e.g. 1.5K-FA TAURUS on ttyACM*) have no fixed vendor id — ignore
# the whole USB CDC-ACM class. Also skips a USB cellular modem on ttyACM if any.
ACTION=="add|change", SUBSYSTEM=="tty", SUBSYSTEMS=="usb", KERNEL=="ttyACM*", ENV{ID_MM_DEVICE_IGNORE}="1"
MM_EOF
chmod 0644 /etc/udev/rules.d/99-spe-remote-mm.rules
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=tty --action=change 2>/dev/null || true

systemctl daemon-reload

# Pre-seed config.json with non-default ports before the daemon ever starts,
# so it binds 8081/8889 on first boot. Only do this if no config exists yet
# (preserves the user's ports across re-installs / upgrades). Qt resolves
# AppConfigLocation = $XDG_CONFIG_HOME/$orgName/$appName/, with orgName
# "spe-remote" and appName "spe-remoted" — that's why this path looks doubly
# nested.
CFG_DIR="$STATE_DIR/spe-remote/spe-remoted"
CFG_FILE="$CFG_DIR/config.json"
if [[ ! -f "$CFG_FILE" ]]; then
    log "Seeding config.json with HTTP=$SPE_HTTP_PORT, WS=$SPE_WS_PORT (no TS-890S clash) …"
    mkdir -p "$CFG_DIR"
    python3 - "$CFG_FILE" "$SPE_HTTP_PORT" "$SPE_WS_PORT" <<'PY'
import json, sys
path, http_port, ws_port = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, "w") as f:
    json.dump({"http_port": http_port, "ws_port": ws_port}, f, indent=2, sort_keys=True)
    f.write("\n")
PY
    chown -R "$TARGET_USER:$TARGET_USER" "$STATE_DIR"
fi

systemctl enable --now spe-remoted

# ------------------------------------------------------------------- #
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
ok "spe-remoted $NEW_TAG is installed and running as user '$TARGET_USER'."
echo
echo "  Status:        systemctl status spe-remoted"
echo "  Live logs:     journalctl -u spe-remoted -f"
echo "  Configure:     sudo spe-config              # change ports, enable Tailscale HTTPS, add instances"
echo
echo "  Browser UI:    http://${IP:-<this-host-ip>}:${SPE_HTTP_PORT}/"
echo "  Settings page: http://${IP:-<this-host-ip>}:${SPE_HTTP_PORT}/settings.html"
echo
echo "  Tailscale + trusted HTTPS guide:"
echo "    https://github.com/$REPO/blob/main/docs/tailscale-setup.md"
