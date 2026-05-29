# Linux (desktop) — install & set up

For a Linux PC **with a screen** running the graphical app. Headless box or
Raspberry Pi with no display? Use the **[Raspberry Pi / headless guide](install-raspberry-pi.md)**
instead (same idea, configured from the browser).

← Back to the [main guide](../README.md).

---

## 1. Install the app

1. Open the **[Releases page](../../releases/latest)**.
2. Download the tarball for your CPU:
   - `spe-remote-qt-<version>-linux-x64.tar.gz` (Intel/AMD)
   - `spe-remote-qt-<version>-linux-arm64.tar.gz` (ARM64)
3. Extract and run:
   ```bash
   tar -xzf spe-remote-qt-*-linux-*.tar.gz
   cd spe-remote-qt-*-linux-*
   ./spe-remote-qt
   ```

The prebuilt binaries dynamically link your system Qt 6. Install the runtime
libraries first (Debian / Ubuntu / Mint / Pi OS):

```bash
sudo apt update
sudo apt install -y \
    libqt6core6 libqt6gui6 libqt6widgets6 libqt6network6 \
    libqt6serialport6 libqt6websockets6 libqt6httpserver6
```

(On a headless server with no display you only need the daemon — see the
[Raspberry Pi guide](install-raspberry-pi.md), which drops the GUI libs and adds
a one-shot installer + systemd setup.)

## 2. Serial port permission (one-time)

Add yourself to the serial group so the app can open the amp's port, then log
out/in:
```bash
sudo usermod -aG dialout "$USER"     # 'uucp' on some distros
```

## 3. Connect the amplifier

1. Plug in the amp by USB and power it on.
2. In the app: **cog (⚙) → Connection settings**.
3. Set **Serial port** (`/dev/ttyUSB0`, ↻ to rescan), **Baud rate**
   (**9600** 1K-FA / **115200** 1.3K–2K-FA), and **Amplifier model**.
4. **Connect**. Locally: **`http://localhost:8080/`**.

## 4. Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```
Sign in (open the printed URL) to your account — see **[Tailscale setup](tailscale-setup.md)**.
Install + sign in on the device you'll operate *from*, same account. One-time in
the [admin console](https://login.tailscale.com/admin/dns): enable **MagicDNS**
(and **HTTPS Certificates** for the padlock). Note this PC's name, e.g. `spe-amp`.

## 5. (Optional) Turn on HTTPS

**Connection settings → Web server security** → **Serve over HTTPS** → **Get
Tailscale certificate** → **Connect**. (Linux uses system OpenSSL — ECDSA certs
work out of the box.) Details: [trusted HTTPS](tailscale-setup.md#trusted-https).

## 6. Operate from anywhere

```
http://spe-amp.your-tailnet.ts.net:8080/      (or https:// if enabled)
```
One-click from another PC: **[SPE Remote Connect](connect-remote-and-phone.md)**.

---

## Keep it running / autostart

Run it at login via your desktop's autostart, or for an always-on box run the
headless **daemon** instead under systemd — see the
**[Raspberry Pi / headless guide](install-raspberry-pi.md)**, which applies to
any Linux server.

## Troubleshooting

- **Permission denied on /dev/ttyUSB0** — you're not in `dialout` yet, or need
  to log out/in (Step 2).
- **Missing Qt libs** — install Qt 6 base (Step 1).
- **No serial port** — check `dmesg | tail` after plugging in; install FTDI
  support if needed; ↻ rescan.
- **Remote / HTTPS issues** — see [Tailscale troubleshooting](tailscale-setup.md#troubleshooting).
