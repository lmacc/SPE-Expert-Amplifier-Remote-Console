# Raspberry Pi (headless) — install & set up

The Pi is the ideal always-on home for SPE Remote: tiny, silent, low-power,
left plugged into the amp. This guide is for a **headless** Pi (no monitor) —
you set everything up from a browser on another device. (It also applies to any
headless Linux server.)

← Back to the [main guide](../README.md).

---

## What runs here

On a headless Pi you run the **daemon** (`spe-remoted`) — same engine as the
desktop app, no screen needed. You configure it (serial port, model, HTTPS)
entirely from the **web Settings page** in your browser.

## Prerequisites

- **64-bit Raspberry Pi OS** (Bookworm or later). There's no prebuilt 32-bit
  binary — use 64-bit Pi OS. (Works equally on any 64-bit Debian/Ubuntu.)
- **Runtime Qt 6 libraries.** The one-shot installer below installs them
  automatically. If you're installing by hand, they are:
  ```bash
  sudo apt update
  sudo apt install -y libqt6core6 libqt6network6 libqt6serialport6 \
                      libqt6websockets6 libqt6httpserver6
  ```

## 1. One-shot install (recommended)

SSH into the Pi and run:

```bash
curl -sSL https://raw.githubusercontent.com/lmacc/SPE-Expert-Amplifier-Remote-Console/main/scripts/install-pi.sh \
  | sudo bash
```

That single command:
- Installs the runtime Qt 6 libraries.
- Downloads the latest prebuilt daemon from the [Releases page](../../releases/latest)
  (verifying the SHA-256 when the release publishes one).
- Extracts it to `/opt/spe-remote/` and symlinks `/usr/local/bin/spe-remoted`.
- Adds your user to the `dialout` group (serial access).
- Drops in a sandboxed **systemd service** (`spe-remoted.service`) and starts it.

When it finishes you'll see the Pi's IP and the URL to open. The web UI is now
on **port 8080**, surviving reboots. Skip to [Step 3](#3-configure-it-from-your-browser).

> **Useful overrides** (set before `sudo bash`):
> - `SPE_TAG=v1.9.5` — pin to a specific release instead of the latest.
> - `SPE_USER=mike` — run the service as this user instead of `$SUDO_USER` / `pi`.
> - `SPE_INSTALL_DIR=/opt/spe` — install elsewhere than `/opt/spe-remote`.

To **upgrade** later, just re-run the same command — the script stops the
service, replaces the files, and starts it again.

### Or — install manually

If you'd rather do it by hand: install the prerequisites above, then:

```bash
sudo mkdir -p /opt/spe-remote
curl -fsSL -o /tmp/spe.tar.gz \
  https://github.com/lmacc/SPE-Expert-Amplifier-Remote-Console/releases/latest/download/spe-remote-qt-<version>-linux-arm64.tar.gz
sudo tar -xzf /tmp/spe.tar.gz -C /opt/spe-remote --strip-components=1
sudo ln -sf /opt/spe-remote/spe-remoted /usr/local/bin/spe-remoted
sudo usermod -aG dialout "$USER"        # log out / in after this
```

(Replace `<version>` with the latest from the [Releases page](../../releases/latest).
For Intel/AMD use `linux-x64` in place of `linux-arm64`.)

## 2. Run it as a service (manual install only)

The one-shot installer above already did this for you — skip to Step 3.

If you installed by hand, create `/etc/systemd/system/spe-remoted.service`:

```ini
[Unit]
Description=SPE Expert Amplifier Remote daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
Group=dialout
Environment=XDG_CONFIG_HOME=/var/lib/spe-remote
StateDirectory=spe-remote
ExecStart=/usr/local/bin/spe-remoted
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Enable and start it:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now spe-remoted
systemctl status spe-remoted          # should be 'active (running)'
```

The web UI is now on **port 8080**. Logs: `journalctl -u spe-remoted -f`.

## 3. Configure it from your browser

Plug the amp into the Pi by USB and power it on. From any device on the same
network (for now), open:

```
http://<pi-ip-or-hostname>:8080/settings.html
```

Set:
- **Serial device** — the amp's port (FTDI ★); ↻ to rescan.
- **Baud rate** — **9600** (1K-FA) / **115200** (1.3K–2K-FA).
- **Amplifier model** — **1K-FA** or **1.3K–2K-FA**.

Click **Apply**. The daemon saves it and connects (and reconnects on boot).
See [amplifier setup](amplifier-setup.md) for the model differences.

## 4. Install Tailscale on the Pi

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```
Open the printed URL to sign in to your account — see **[Tailscale setup](tailscale-setup.md)**.
Install + sign in on the device you'll operate *from*, same account. One-time in
the [admin console](https://login.tailscale.com/admin/dns): enable **MagicDNS**
(and **HTTPS Certificates** for the padlock). Note the Pi's name, e.g. `spe-amp`.

## 5. Turn on HTTPS — from the browser, no SSH

On the **Settings page** (`http://<pi>:8080/settings.html`) → **Web server
security** → **Get Tailscale certificate**. The daemon fetches a trusted cert,
switches itself to HTTPS, and the page reloads over `https://` — no terminal,
no config editing, no restart. Details:
[trusted HTTPS](tailscale-setup.md#trusted-https).

## 6. Operate from anywhere

```
https://spe-amp.your-tailnet.ts.net:8080/
```
The Pi stays plugged in at home; you reach it from anywhere on your tailnet.
One-click from another PC: **[SPE Remote Connect](connect-remote-and-phone.md)**.

---

## Updating

Just re-run the one-shot installer — it stops the service, replaces the files,
restores ownership, and starts it again:

```bash
curl -sSL https://raw.githubusercontent.com/lmacc/SPE-Expert-Amplifier-Remote-Console/main/scripts/install-pi.sh \
  | sudo bash
```

To pin a specific release: `sudo SPE_TAG=v1.9.5 bash <(curl -sSL …)`.

## Troubleshooting

- **Service won't start** — `journalctl -u spe-remoted -e`; check the binary
  path and that the arch matches (64-bit Pi OS for the arm64 build).
- **No serial device in Settings** — amp powered + USB seated; `pi` in
  `dialout` and re-logged-in; ↻ rescan.
- **`tailscale cert` button greyed out / fails** — install Tailscale on the Pi
  and enable HTTPS Certificates + MagicDNS in the admin console
  ([troubleshooting](tailscale-setup.md#troubleshooting)).
