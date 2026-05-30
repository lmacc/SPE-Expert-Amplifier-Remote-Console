#!/usr/bin/env bash
#
# install-pi.sh — one-shot installer for the SPE Expert Amplifier Remote
# daemon on a 64-bit Raspberry Pi OS (or any 64-bit Debian/Ubuntu box).
#
# Downloads the latest prebuilt binary from the public Releases, installs
# the runtime Qt 6 libraries, drops in a systemd service, and starts it.
# No build, no source clone — runs from a single curl|bash command.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/lmacc/SPE-Expert-Amplifier-Remote-Console/main/scripts/install-pi.sh | sudo bash
#
# Or, from a local copy:
#   sudo bash install-pi.sh
#
# Options (set as environment variables, before sudo, e.g. `sudo SPE_USER=mike bash …`):
#   SPE_TAG=v1.9.6           Pin to a specific release (default: latest).
#   SPE_USER=mike            Service runs as this user (default: $SUDO_USER or pi).
#   SPE_INSTALL_DIR=/opt/X   Install path (default: /opt/spe-remote).
#
set -euo pipefail

REPO="lmacc/SPE-Expert-Amplifier-Remote-Console"
TAG="${SPE_TAG:-latest}"
INSTALL_DIR="${SPE_INSTALL_DIR:-/opt/spe-remote}"
SERVICE_DST="/etc/systemd/system/spe-remoted.service"
BIN_LINK="/usr/local/bin/spe-remoted"
TARGET_USER="${SPE_USER:-${SUDO_USER:-pi}}"

# ------------------------------------------------------------------- #
log()  { printf '\033[36m[install-pi]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[install-pi]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[install-pi]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[install-pi]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (use sudo)."
id "$TARGET_USER" >/dev/null 2>&1 \
    || die "Target user '$TARGET_USER' does not exist. Set SPE_USER=<name>."

# ------------------------------------------------------------------- #
# Architecture → release asset suffix.
# ------------------------------------------------------------------- #
case "$(uname -m)" in
    aarch64|arm64) ARCH="linux-arm64" ;;
    x86_64|amd64)  ARCH="linux-x64"   ;;
    *) die "Unsupported architecture: $(uname -m). Prebuilt binaries cover linux-x64 and linux-arm64 only." ;;
esac
log "Architecture: $ARCH   service user: $TARGET_USER"

# ------------------------------------------------------------------- #
# Runtime Qt 6 libraries the prebuilt daemon links against (dynamic).
# These are the only runtime deps; no GUI / no widgets needed.
# ------------------------------------------------------------------- #
log "Installing prerequisites (apt) …"
# The tarball bundles its own Qt 6 (libs + tls plugin) under lib/ next to
# the binary, so we don't need system Qt packages — the daemon uses the
# bundled libraries via RPATH regardless of what the distro ships.
apt-get update -qq
apt-get install -y --no-install-recommends \
    curl ca-certificates tar \
    >/dev/null

# ------------------------------------------------------------------- #
# Find the latest release tag and the matching tarball URL on the
# public repo. No `jq` dependency.
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
[[ -n "$ASSET_URL" ]] \
    || die "No asset matching '${ARCH}' on release $NEW_TAG."
ASSET_NAME="$(basename "$ASSET_URL")"

# Optional SHA-256 verification — GitHub publishes a digest field per asset
# on newer releases. Skip silently if absent.
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

# Try up to 3 times. On a flaky Wi-Fi link the download occasionally arrives
# truncated; the SHA-256 check catches it and we retry instead of giving up.
DOWNLOAD_OK=0
for attempt in 1 2 3; do
    log "Downloading $ASSET_NAME (attempt $attempt/3) …"
    rm -f "$ARCHIVE"
    # No custom User-Agent: a non-standard UA can trip ISP/CDN caches into
    # serving a stale or wrong object. Cache-Control headers ask any
    # intermediate proxies to revalidate rather than serve a cached copy.
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
        warn "  expected $EXPECTED_SHA"
        warn "  got      $ACTUAL_SHA"
    else
        warn "Download failed on attempt $attempt (curl exit code $?)."
    fi
    [[ $attempt -lt 3 ]] && sleep 2
done

[[ "$DOWNLOAD_OK" == "1" ]] \
    || die "Could not get a valid archive after 3 attempts. Check the network and try again."

# Stop the service first so we don't replace a busy binary (upgrade path).
if systemctl is-active --quiet spe-remoted 2>/dev/null; then
    log "Stopping existing spe-remoted service for upgrade …"
    systemctl stop spe-remoted || true
fi

log "Extracting to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
tar -xzf "$ARCHIVE" -C "$INSTALL_DIR" --strip-components=1
chown -R "$TARGET_USER":"$TARGET_USER" "$INSTALL_DIR"

# Convenience symlink so `spe-remoted --help` works from anywhere.
ln -sf "$INSTALL_DIR/spe-remoted" "$BIN_LINK"

# Sanity check: actually run the binary once and confirm it starts cleanly
# (--version exits 0 and prints, never opens any sockets). Catches Qt-ABI
# / missing-library issues here, with a clear error, instead of via a
# systemd restart loop later.
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
# Serial access + systemd unit.
# ------------------------------------------------------------------- #
log "Adding $TARGET_USER to the dialout group (serial access) …"
usermod -a -G dialout "$TARGET_USER" || true

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

# Persist config (config.json + tls/) under StateDirectory, so the web
# Settings page can save the serial port + HTTPS cert paths even with
# ProtectHome=true. Resolves to /var/lib/spe-remote/spe-remoted/.
Environment=XDG_CONFIG_HOME=/var/lib/spe-remote
StateDirectory=spe-remote

ExecStart=$BIN_LINK
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

# Light sandboxing — the daemon only needs the serial device and the network.
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
DeviceAllow=/dev/ttyUSB0 rw
DeviceAllow=/dev/ttyUSB1 rw
DeviceAllow=/dev/ttyAMA0 rw
DeviceAllow=/dev/serial0 rw

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$SERVICE_DST"

systemctl daemon-reload
systemctl enable --now spe-remoted

# ------------------------------------------------------------------- #
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
ok "spe-remoted $NEW_TAG is installed and running as user '$TARGET_USER'."
echo
echo "  Status:        systemctl status spe-remoted"
echo "  Live logs:     journalctl -u spe-remoted -f"
echo
echo "  Browser UI:    http://${IP:-<this-pi-ip>}:8080/"
echo "  Settings page: http://${IP:-<this-pi-ip>}:8080/settings.html"
echo "                 (pick serial port + amp model from any browser)"
echo
echo "  Tailscale + trusted HTTPS guide:"
echo "    https://github.com/$REPO/blob/main/docs/tailscale-setup.md"
