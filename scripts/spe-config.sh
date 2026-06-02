#!/usr/bin/env bash
#
# spe-config — interactive helper for the SPE Expert Amplifier Remote
# daemon. Run as root (sudo spe-config).
#
# Supports multiple instances on one host. The first instance (installed
# by install.sh) lives at:
#   /etc/systemd/system/spe-remoted.service
#   /var/lib/spe-remote/
# Extra instances added via this tool live at:
#   /etc/systemd/system/spe-remoted-<NAME>.service
#   /var/lib/spe-remote-<NAME>/
#
# Each instance has its own config.json (ports, serial port, amp model,
# cert paths), so two amps can run on the same Pi without colliding.
#
set -euo pipefail

REPO="lmacc/SPE-Expert-Amplifier-Remote-Console"
BIN_LINK="/usr/local/bin/spe-remoted"
TARGET_USER_DEFAULT="${SUDO_USER:-pi}"

# ------------------------------------------------------------------- #
# Pretty output.
# ------------------------------------------------------------------- #
c_cyan()  { printf '\033[36m%s\033[0m' "$*"; }
c_green() { printf '\033[32m%s\033[0m' "$*"; }
c_yel()   { printf '\033[33m%s\033[0m' "$*"; }
c_red()   { printf '\033[31m%s\033[0m' "$*"; }
log()  { printf '%s %s\n' "$(c_cyan '[spe-config]')" "$*"; }
ok()   { printf '%s %s\n' "$(c_green '[spe-config]')" "$*"; }
warn() { printf '%s %s\n' "$(c_yel  '[spe-config]')" "$*" >&2; }
die()  { printf '%s %s\n' "$(c_red  '[spe-config]')" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (use sudo)."
command -v python3 >/dev/null || die "python3 is required (apt install python3)."

# ------------------------------------------------------------------- #
# Instance discovery.  Returns a newline-separated list of unit names
# (e.g. "spe-remoted.service", "spe-remoted-amp2.service").
# ------------------------------------------------------------------- #
list_instances() {
    systemctl list-unit-files --no-legend --no-pager 'spe-remoted*.service' 2>/dev/null \
        | awk '{print $1}' \
        | grep -E '^spe-remoted(-.+)?\.service$' \
        | sort
}

# Given a unit name, derive the state dir and the config.json path Qt uses.
# Qt's AppConfigLocation = $XDG_CONFIG_HOME/$orgName/$appName/, with
# orgName="spe-remote" and appName="spe-remoted".
instance_state_dir() {
    local unit="$1"
    local suffix="${unit#spe-remoted}"
    suffix="${suffix%.service}"   # "" for primary, "-amp2" for spe-remoted-amp2
    echo "/var/lib/spe-remote${suffix}"
}
instance_config_path() {
    local unit="$1"
    echo "$(instance_state_dir "$unit")/spe-remote/spe-remoted/config.json"
}
instance_name() {
    local unit="$1"
    local suffix="${unit#spe-remoted}"
    suffix="${suffix%.service}"
    if [[ -z "$suffix" ]]; then echo "(primary)"; else echo "${suffix#-}"; fi
}

# ------------------------------------------------------------------- #
# config.json read/write via python3 (no jq dependency).
# ------------------------------------------------------------------- #
cfg_read() {  # cfg_read <path> <key> [default]
    local path="$1" key="$2" default="${3:-}"
    if [[ ! -f "$path" ]]; then echo "$default"; return; fi
    python3 - "$path" "$key" "$default" <<'PY'
import json, sys
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f: d = json.load(f)
except Exception:
    print(default); sys.exit(0)
v = d.get(key, default)
print("" if v is None else v)
PY
}

cfg_write() {  # cfg_write <path> <key=value> [key=value]…  (values are JSON-encoded)
    local path="$1"; shift
    mkdir -p "$(dirname "$path")"
    [[ -f "$path" ]] || echo '{}' > "$path"
    python3 - "$path" "$@" <<'PY'
import json, os, sys
path, *pairs = sys.argv[1:]
d = {}
if os.path.exists(path):
    with open(path) as f:
        txt = f.read().strip()
        if txt:
            d = json.loads(txt)
for p in pairs:
    k, v = p.split("=", 1)
    # Coerce to int / bool / null where it makes sense; otherwise keep as string.
    if v in ("true", "false"):    d[k] = (v == "true")
    elif v == "null":             d[k] = None
    elif v.lstrip("-").isdigit(): d[k] = int(v)
    else:                          d[k] = v
with open(path, "w") as f:
    json.dump(d, f, indent=2, sort_keys=True)
    f.write("\n")
PY
}

# ------------------------------------------------------------------- #
# Pick an instance: prompts if there's more than one, returns the unit
# name on stdout. Echoes status to stderr only.
# ------------------------------------------------------------------- #
pick_instance() {
    local -a instances
    mapfile -t instances < <(list_instances)
    if [[ ${#instances[@]} -eq 0 ]]; then
        die "No spe-remoted services found. Run the installer first."
    fi
    if [[ ${#instances[@]} -eq 1 ]]; then
        echo "${instances[0]}"; return
    fi
    {
        echo "Multiple instances installed:"
        local i=1
        for u in "${instances[@]}"; do
            printf "  %d) %-30s  name: %s\n" "$i" "$u" "$(instance_name "$u")"
            ((i++))
        done
        printf "Pick one [1-%d]: " "${#instances[@]}"
    } >&2
    local choice
    read -r choice
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#instances[@]} )) \
        || die "Invalid selection."
    echo "${instances[choice-1]}"
}

# ------------------------------------------------------------------- #
# Show an instance's current config.
# ------------------------------------------------------------------- #
show_instance() {
    local unit="$1"
    local cfg="$(instance_config_path "$unit")"
    local state="$(instance_state_dir "$unit")"
    echo
    echo "  Unit:         $unit"
    echo "  Name:         $(instance_name "$unit")"
    echo "  State dir:    $state"
    echo "  Config file:  $cfg"
    echo
    if [[ -f "$cfg" ]]; then
        echo "  Serial port:  $(cfg_read "$cfg" port '(not set)')"
        echo "  Baud rate:    $(cfg_read "$cfg" baud 115200)"
        echo "  Amp model:    $(cfg_read "$cfg" amp_model '(not set)')"
        echo "  HTTP port:    $(cfg_read "$cfg" http_port 8080)"
        echo "  WS port:      $(cfg_read "$cfg" ws_port 8888)"
        local cert="$(cfg_read "$cfg" cert_file '')"
        local key="$(cfg_read "$cfg" key_file '')"
        if [[ -n "$cert" ]]; then
            echo "  TLS cert:     $cert"
            echo "  TLS key:      $key"
        else
            echo "  TLS:          (off — plain HTTP)"
        fi
    else
        echo "  Config file not yet written (start the service once to create it)."
    fi
    echo
    systemctl --no-pager --lines=0 status "$unit" 2>/dev/null \
        | grep -E '^\s+Active:' || true
    echo
}

# ------------------------------------------------------------------- #
# Action: change a port (HTTP or WS).
# ------------------------------------------------------------------- #
change_port() {
    local unit="$1"
    local which="$2"   # "http_port" or "ws_port"
    local label="$3"   # human label
    local cfg="$(instance_config_path "$unit")"
    local current
    current="$(cfg_read "$cfg" "$which" $([[ "$which" == http_port ]] && echo 8080 || echo 8888))"
    printf "Current %s port: %s\nNew %s port (1024-65535, Enter to keep): " \
        "$label" "$current" "$label"
    local new
    read -r new
    [[ -z "$new" ]] && { echo "Unchanged."; return; }
    [[ "$new" =~ ^[0-9]+$ ]] && (( new >= 1024 && new <= 65535 )) \
        || die "Invalid port: $new"
    # Quick conflict check against other instances on this host.
    local other_unit
    while IFS= read -r other_unit; do
        [[ "$other_unit" == "$unit" ]] && continue
        local other_cfg="$(instance_config_path "$other_unit")"
        [[ -f "$other_cfg" ]] || continue
        local other_http="$(cfg_read "$other_cfg" http_port 8080)"
        local other_ws="$(cfg_read "$other_cfg" ws_port 8888)"
        if [[ "$new" == "$other_http" || "$new" == "$other_ws" ]]; then
            die "Port $new is already used by $other_unit. Pick another."
        fi
    done < <(list_instances)
    cfg_write "$cfg" "$which=$new"
    chown -R "$(stat -c %U "$(instance_state_dir "$unit")")" "$(dirname "$cfg")" 2>/dev/null || true
    ok "Set $label port to $new — restarting $unit …"
    systemctl restart "$unit"
}

# ------------------------------------------------------------------- #
# Action: enable Let's Encrypt HTTPS for an instance.
# Requires:
#   - A public DNS name pointing at this host's public IP
#   - Port 80 reachable inbound (for the HTTP-01 challenge)
# Installs certbot, runs --standalone, copies the cert+key to a
# daemon-readable spot, installs a deploy hook for renewals, points the
# daemon at the copies, restarts.
# ------------------------------------------------------------------- #
enable_letsencrypt() {
    local unit="$1"
    local cfg="$(instance_config_path "$unit")"
    local state="$(instance_state_dir "$unit")"
    local svc_user
    svc_user="$(systemctl show -p User --value "$unit")"
    [[ -z "$svc_user" || "$svc_user" == "[not set]" ]] && svc_user="$TARGET_USER_DEFAULT"

    echo
    echo "Let's Encrypt issues free, browser-trusted certificates."
    echo "Requirements:"
    echo "  1. A public DNS name (e.g. mypi.example.com) pointing at THIS host's public IP."
    echo "  2. Port 80 reachable from the internet for ~30 seconds during the challenge."
    echo "     (After issuance you can close port 80 again — renewals reopen it briefly.)"
    echo
    printf "Hostname (e.g. mypi.example.com): "
    local host; read -r host
    [[ -n "$host" ]] || die "Hostname is required."
    printf "Contact email (used by Let's Encrypt for expiry warnings): "
    local email; read -r email
    [[ -n "$email" ]] || die "Email is required."

    if ! command -v certbot >/dev/null; then
        log "Installing certbot (apt) …"
        apt-get update -qq
        apt-get install -y --no-install-recommends certbot >/dev/null
    fi

    # Stop the instance only if it's currently listening on port 80 — usually
    # it isn't, but certbot --standalone needs port 80 free either way.
    log "Asking certbot to issue a certificate for $host …"
    certbot certonly --standalone --preferred-challenges http \
        -d "$host" --email "$email" \
        --agree-tos --no-eff-email --non-interactive \
        || die "certbot failed. Check that '$host' resolves to this host's public IP and port 80 is reachable."

    local le_dir="/etc/letsencrypt/live/$host"
    [[ -f "$le_dir/fullchain.pem" && -f "$le_dir/privkey.pem" ]] \
        || die "Cert not found at $le_dir after certbot — aborting."

    # Copy the cert+key to a daemon-readable location. /etc/letsencrypt/{live,archive}
    # are mode 0700 root:root by default, which means the unprivileged daemon
    # can't read privkey.pem directly. The deploy hook below keeps these in sync.
    local dest_dir="$state/tls/letsencrypt"
    mkdir -p "$dest_dir"
    cp -L "$le_dir/fullchain.pem" "$dest_dir/$host.crt"
    cp -L "$le_dir/privkey.pem"   "$dest_dir/$host.key"
    chown -R "$svc_user:$svc_user" "$dest_dir"
    chmod 0640 "$dest_dir/$host.crt" "$dest_dir/$host.key"

    # Install a renewal deploy hook that mirrors the same copy + reload after
    # every certbot renewal. certbot runs this only when it actually renews,
    # so the daemon doesn't get pointlessly restarted every day.
    local hook="/etc/letsencrypt/renewal-hooks/deploy/spe-remoted-${unit%.service}.sh"
    mkdir -p "$(dirname "$hook")"
    cat > "$hook" <<EOF
#!/usr/bin/env bash
# Auto-generated by spe-config for unit: $unit, host: $host.
set -euo pipefail
case "\$RENEWED_LINEAGE" in
    */live/$host) ;;
    *) exit 0 ;;
esac
DEST="$dest_dir"
cp -L "\$RENEWED_LINEAGE/fullchain.pem" "\$DEST/$host.crt"
cp -L "\$RENEWED_LINEAGE/privkey.pem"   "\$DEST/$host.key"
chown $svc_user:$svc_user "\$DEST/$host.crt" "\$DEST/$host.key"
chmod 0640 "\$DEST/$host.crt" "\$DEST/$host.key"
systemctl restart $unit
EOF
    chmod 0755 "$hook"

    # Point the daemon at the new cert+key, then restart.
    mkdir -p "$(dirname "$cfg")"
    chown -R "$svc_user:$svc_user" "$state"
    cfg_write "$cfg" "cert_file=$dest_dir/$host.crt" "key_file=$dest_dir/$host.key"
    chown "$svc_user:$svc_user" "$cfg"
    systemctl restart "$unit"

    local port="$(cfg_read "$cfg" http_port 8080)"
    echo
    ok "Let's Encrypt enabled for $host on $unit."
    echo "  Browse to: https://$host:$port/"
    echo "  Renewal hook: $hook (runs automatically after each certbot renewal)"
    echo
}

# ------------------------------------------------------------------- #
# Action: turn HTTPS off (clear cert paths).
# ------------------------------------------------------------------- #
disable_https() {
    local unit="$1"
    local cfg="$(instance_config_path "$unit")"
    cfg_write "$cfg" "cert_file=" "key_file="
    ok "HTTPS disabled on $unit — restarting …"
    systemctl restart "$unit"
}

# ------------------------------------------------------------------- #
# Action: add a new instance (second amp on the same host).
# ------------------------------------------------------------------- #
add_instance() {
    printf "Short name for the new instance (letters/digits/dashes, e.g. amp2): "
    local name; read -r name
    [[ "$name" =~ ^[a-z0-9-]+$ ]] || die "Invalid name. Use lowercase letters, digits, and dashes."
    [[ "$name" == primary ]] && die "Reserved name."

    local unit="spe-remoted-${name}.service"
    local service_file="/etc/systemd/system/$unit"
    [[ -e "$service_file" ]] && die "An instance named '$name' already exists."

    printf "HTTP port for this instance (Enter for 8090): "
    local http_port; read -r http_port; http_port="${http_port:-8090}"
    printf "WebSocket port for this instance (Enter for 8898): "
    local ws_port; read -r ws_port; ws_port="${ws_port:-8898}"
    printf "Serial device (e.g. /dev/ttyUSB1, Enter to set later via the web UI): "
    local serial; read -r serial

    local target_user="${SUDO_USER:-${TARGET_USER_DEFAULT}}"
    local state="/var/lib/spe-remote-${name}"

    # Drop a config.json with the chosen ports + serial pre-populated, so the
    # daemon starts cleanly on the right ports instead of grabbing 8080.
    local cfg="$state/spe-remote/spe-remoted/config.json"
    mkdir -p "$(dirname "$cfg")"
    local pairs=("http_port=$http_port" "ws_port=$ws_port")
    [[ -n "$serial" ]] && pairs+=("port=$serial")
    cfg_write "$cfg" "${pairs[@]}"
    chown -R "$target_user:$target_user" "$state"

    cat > "$service_file" <<EOF
[Unit]
Description=SPE Expert Amplifier Remote daemon (instance: $name)
Documentation=https://github.com/$REPO
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$target_user
Group=dialout

Environment=XDG_CONFIG_HOME=$state
StateDirectory=spe-remote-${name}

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
ReadOnlyPaths=/etc/letsencrypt
DeviceAllow=/dev/ttyUSB0 rw
DeviceAllow=/dev/ttyUSB1 rw
DeviceAllow=/dev/ttyUSB2 rw
DeviceAllow=/dev/ttyAMA0 rw
DeviceAllow=/dev/serial0 rw

[Install]
WantedBy=multi-user.target
EOF
    chmod 0644 "$service_file"

    systemctl daemon-reload
    systemctl enable --now "$unit"

    local ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo
    ok "Instance '$name' added — listening on http://${ip:-<host>}:${http_port}/"
}

# ------------------------------------------------------------------- #
# Action: remove a non-primary instance.
# ------------------------------------------------------------------- #
remove_instance() {
    local unit="$1"
    [[ "$unit" == "spe-remoted.service" ]] \
        && die "Refusing to remove the primary instance — use the uninstaller for that."
    printf "Really remove %s and wipe its config dir? [y/N]: " "$unit"
    local yn; read -r yn
    [[ "$yn" =~ ^[yY] ]] || { echo "Aborted."; return; }
    systemctl stop "$unit" 2>/dev/null || true
    systemctl disable "$unit" 2>/dev/null || true
    rm -f "/etc/systemd/system/$unit"
    systemctl daemon-reload
    rm -rf "$(instance_state_dir "$unit")"
    # Also drop any Let's Encrypt deploy hook for this instance.
    rm -f "/etc/letsencrypt/renewal-hooks/deploy/spe-remoted-${unit%.service}.sh"
    ok "Instance $unit removed."
}

# ------------------------------------------------------------------- #
# Main menu loop.
# ------------------------------------------------------------------- #
main_menu() {
    local unit
    unit="$(pick_instance)"
    while true; do
        show_instance "$unit"
        cat <<MENU
What would you like to do?
  1) Change HTTP port
  2) Change WebSocket port
  3) Enable Let's Encrypt HTTPS (public hostname required)
  4) Disable HTTPS
  5) Restart this instance
  6) Show live logs (Ctrl-C to stop)
  7) Switch to a different instance
  8) Add a new instance (second amp on this host)
  9) Remove this instance
  0) Quit
MENU
        printf "Choice: "
        local ch; read -r ch
        case "$ch" in
            1) change_port "$unit" http_port "HTTP" ;;
            2) change_port "$unit" ws_port   "WebSocket" ;;
            3) enable_letsencrypt "$unit" ;;
            4) disable_https "$unit" ;;
            5) systemctl restart "$unit" && ok "Restarted." ;;
            6) journalctl -u "$unit" -f ;;
            7) unit="$(pick_instance)" ;;
            8) add_instance ;;
            9) remove_instance "$unit"; unit="$(pick_instance)" ;;
            0) exit 0 ;;
            *) warn "Pick a number from the menu." ;;
        esac
    done
}

main_menu
