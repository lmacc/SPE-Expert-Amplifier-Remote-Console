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

cfg_delete() {  # cfg_delete <path> <key>…  (removes keys if present)
    local path="$1"; shift
    [[ -f "$path" ]] || return 0
    python3 - "$path" "$@" <<'PY'
import json, sys
path, *keys = sys.argv[1:]
try:
    with open(path) as f: d = json.load(f)
except Exception:
    sys.exit(0)
for k in keys:
    d.pop(k, None)
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
# Action: enable HTTPS for this instance via `tailscale serve`.
# This runs a reverse proxy on the host's Tailscale node that mounts:
#   https://<tailnet>:<https_port>/    →  http://localhost:<http_port>
#   https://<tailnet>:<https_port>/ws  →  http://localhost:<ws_port>
# Tailscale provisions a real, browser-trusted Let's Encrypt cert for the
# tailnet name automatically (30-60 s on first use). No public DNS, no
# port 80 inbound, no certbot, no deploy hooks. Survives reboots; renews
# itself. Stacks cleanly with other services (e.g. a TS-890S webserver)
# by putting them on different HTTPS ports.
# ------------------------------------------------------------------- #
tailnet_name() {
    tailscale status --json 2>/dev/null \
        | grep -m1 '"DNSName"' \
        | sed -E 's/.*"DNSName":\s*"([^"]+)\.".*/\1/' \
        || echo ""
}

# Wrapper for `tailscale serve`: the CLI flag syntax changed across versions
# (1.50+ uses --set-path; older builds accept a positional path). Try the
# modern form first, fall through to the legacy form on failure.
ts_serve_add() {
    local https_port="$1" path="$2" target="$3"
    tailscale serve --bg --https="$https_port" --set-path="$path" "$target" 2>/dev/null \
        && return 0
    tailscale serve --bg --https="$https_port"                 "$path" "$target" 2>/dev/null \
        && return 0
    tailscale serve https / "$target"
}
ts_serve_remove() {
    local https_port="$1" path="$2"
    tailscale serve --https="$https_port" --set-path="$path" off 2>/dev/null || true
    tailscale serve --https="$https_port"                 "$path" off 2>/dev/null || true
}

enable_tailscale_https() {
    local unit="$1"
    local cfg="$(instance_config_path "$unit")"

    if ! command -v tailscale >/dev/null; then
        warn "Tailscale isn't installed on this host. Install it first:"
        echo "    curl -fsSL https://tailscale.com/install.sh | sh"
        echo "    sudo tailscale up"
        return
    fi
    if ! tailscale status >/dev/null 2>&1; then
        warn "Tailscale is installed but not signed in. Run 'sudo tailscale up' first."
        return
    fi

    local http_port="$(cfg_read "$cfg" http_port 8080)"
    local ws_port="$(cfg_read   "$cfg" ws_port   8888)"
    local name; name="$(tailnet_name)"
    [[ -n "$name" ]] || { warn "Couldn't determine this host's tailnet name."; return; }

    # Pick an HTTPS port. 443 is the obvious default; if it's already in use
    # by another `tailscale serve` mount, ask for a different one.
    local in_use_443
    in_use_443="$(tailscale serve status 2>/dev/null | grep -c 'https://[^ ]*:443' || true)"
    local default_port=443
    if [[ "$in_use_443" -gt 0 ]]; then
        default_port=8443
        warn "HTTPS port 443 already has a tailscale serve mount — using $default_port for this instance."
    fi
    printf "Tailscale HTTPS port to use [%d]: " "$default_port"
    local https_port; read -r https_port
    https_port="${https_port:-$default_port}"
    [[ "$https_port" =~ ^[0-9]+$ ]] && (( https_port >= 1 && https_port <= 65535 )) \
        || die "Invalid HTTPS port."

    local url_root
    if [[ "$https_port" == 443 ]]; then url_root="https://${name}"
    else                                url_root="https://${name}:${https_port}"
    fi
    echo
    echo "About to configure:"
    echo "  ${url_root}/    →  http://localhost:${http_port}    (web UI)"
    echo "  ${url_root}/ws  →  http://localhost:${ws_port}      (websocket)"
    echo
    echo "Tailscale will fetch a real Let's Encrypt cert for ${name} on first"
    echo "use (30-60 seconds). No public DNS or port 80 needed."
    echo
    printf "Proceed? [Y/n]: "
    local yn; read -r yn
    [[ "${yn,,}" == "n" ]] && { echo "Aborted."; return; }

    log "Adding tailscale serve mounts …"
    ts_serve_add "$https_port" "/"   "http://localhost:${http_port}" \
        || die "tailscale serve failed for / — see 'sudo tailscale serve status'."
    ts_serve_add "$https_port" "/ws" "http://localhost:${ws_port}" \
        || warn "WS mount failed — root mount is up. Check 'sudo tailscale serve status'."

    echo
    ok "Tailscale HTTPS enabled for $unit."
    echo "  Open: ${url_root}/"
    if command -v qrencode >/dev/null 2>&1; then
        echo
        qrencode -t ANSI256 -m 1 "${url_root}/"
    else
        echo "  (install 'qrencode' to also print a QR for your phone:  sudo apt install qrencode)"
    fi
    echo
}

disable_https() {
    local unit="$1"
    local cfg="$(instance_config_path "$unit")"
    local http_port="$(cfg_read "$cfg" http_port 8080)"
    local changed=0

    # 1) Remove any Tailscale serve mounts that proxy to this instance.
    if command -v tailscale >/dev/null; then
        local matches
        matches="$(tailscale serve status 2>/dev/null \
                    | grep -E "https://[^ ]+:[0-9]+/(ws)?[[:space:]]" \
                    | awk -v t="http://localhost:${http_port}" '$0 ~ t {print $1}' \
                    | grep -oE ':[0-9]+/' | tr -d ':/' | sort -u)"
        if [[ -n "$matches" ]]; then
            for p in $matches; do
                log "Removing tailscale serve mounts on HTTPS port $p …"
                ts_serve_remove "$p" "/"
                ts_serve_remove "$p" "/ws"
            done
            changed=1
        fi
    fi

    # 2) Clear the daemon's NATIVE TLS (cert_file / key_file) from config.json.
    # This is what actually decides whether the daemon binds HTTPS — the web UI
    # cert fetch / setup-https set these, and removing serve mounts alone does
    # NOT turn native TLS off. Without this step "Disable HTTPS" appears to do
    # nothing: the daemon keeps serving HTTPS from the still-present cert/key.
    local cert="$(cfg_read "$cfg" cert_file '')"
    local key="$(cfg_read  "$cfg" key_file  '')"
    if [[ -n "$cert" || -n "$key" ]]; then
        log "Clearing native TLS cert/key from $cfg …"
        cfg_delete "$cfg" cert_file key_file
        chown -R "$(stat -c %U "$(instance_state_dir "$unit")")" "$(dirname "$cfg")" 2>/dev/null || true
        changed=1
    fi

    if [[ "$changed" -eq 0 ]]; then
        warn "HTTPS wasn't enabled for $unit (no serve mounts and no cert/key in config) — nothing to do."
        return
    fi

    ok "HTTPS disabled for $unit — restarting so it serves plain HTTP on :${http_port} …"
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
DeviceAllow=/dev/ttyUSB3 rw
# Newer amps (e.g. 1.5K-FA TAURUS) enumerate as USB-CDC devices, which
# appear as /dev/ttyACM* rather than /dev/ttyUSB* — without these lines the
# sandbox denies the port even though the web UI can still list it.
DeviceAllow=/dev/ttyACM0 rw
DeviceAllow=/dev/ttyACM1 rw
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
  3) Enable HTTPS via Tailscale Serve (browser-trusted padlock, no public DNS)
  4) Disable HTTPS (clear native cert/key + remove Tailscale serve mounts)
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
            3) enable_tailscale_https  "$unit" ;;
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
