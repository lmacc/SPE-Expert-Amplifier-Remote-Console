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

## 1. Install the daemon

SSH into the Pi, then:

```bash
# Pick your arch: arm64 (64-bit Pi OS, recommended) shown here.
curl -fsSL -o spe.tar.gz \
  https://github.com/lmacc/SPE-Expert-Amplifier-Remote-Console/releases/latest/download/spe-remote-qt-<version>-linux-arm64.tar.gz
sudo mkdir -p /opt/spe-remote
sudo tar -xzf spe.tar.gz -C /opt/spe-remote --strip-components=1
```

> Replace `<version>` with the latest (see the [Releases page](../../releases/latest)).
> 32-bit Pi OS: there's no prebuilt 32-bit binary — use 64-bit Pi OS.

Add the `pi` user to the serial group (one-time), then re-login:
```bash
sudo usermod -aG dialout pi
```

## 2. Run it as a service (starts on boot)

Create `/etc/systemd/system/spe-remoted.service`:

```ini
[Unit]
Description=SPE Expert Amplifier Remote daemon
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/opt/spe-remote/spe-remoted
Restart=on-failure
User=pi

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

```bash
sudo systemctl stop spe-remoted
# download the new tarball as in Step 1, extract over /opt/spe-remote
sudo systemctl start spe-remoted
```

## Troubleshooting

- **Service won't start** — `journalctl -u spe-remoted -e`; check the binary
  path and that the arch matches (64-bit Pi OS for the arm64 build).
- **No serial device in Settings** — amp powered + USB seated; `pi` in
  `dialout` and re-logged-in; ↻ rescan.
- **`tailscale cert` button greyed out / fails** — install Tailscale on the Pi
  and enable HTTPS Certificates + MagicDNS in the admin console
  ([troubleshooting](tailscale-setup.md#troubleshooting)).
