# macOS — install & set up

Full walkthrough: install the app, connect your SPE Expert amp, set up Tailscale,
and reach it from anywhere (with HTTPS). ~15 minutes.

← Back to the [main guide](../README.md).

---

## 1. Install the app

1. Open the **[Releases page](../../releases/latest)**.
2. Download **`spe-remote-qt-<version>-macos-arm64.dmg`** (Apple Silicon).
3. Open the `.dmg` and **drag** `spe-remote-qt.app` (and `spe-connect.app`, the
   remote-operate helper) into your **Applications** folder.

> First launch: because the build isn't notarised, macOS may say it "can't be
> opened." **Right-click the app → Open → Open**, once. After that it launches
> normally.

## 2. Connect the amplifier

1. Plug the amp into the Mac by USB and power it on.
2. Launch **spe-remote-qt** from Applications.
3. Click the **cog** (⚙) → **Connection settings**.
4. Set:
   - **Serial port** — the amp's `/dev/cu.usbserial-…` (FTDI) entry; hit ↻ to
     rescan.
   - **Baud rate** — **9600** (1K-FA) or **115200** (1.3K / 1.5K / 2K-FA).
   - **Amplifier model** — **1K-FA** or **1.3K–2K-FA** (see
     [amplifier setup](amplifier-setup.md)).
5. Click **Connect**. Locally it's now at **`http://localhost:8080/`**.

> If no serial port shows, install the FTDI VCP driver for macOS, replug, ↻.

## 3. Install Tailscale

1. Install from **[tailscale.com/download/mac](https://tailscale.com/download/mac)**
   (App Store or standalone), and sign in — see **[Tailscale setup](tailscale-setup.md)**.
2. Install + sign in Tailscale on the device you'll operate *from*, same account.
3. One-time in the [admin console](https://login.tailscale.com/admin/dns): enable
   **MagicDNS** (and **HTTPS Certificates** for the padlock). Note this Mac's
   name in [Machines](https://login.tailscale.com/admin/machines), e.g. `spe-amp`.

## 4. (Optional) Turn on HTTPS

**Connection settings → Web server security** → tick **Serve over HTTPS** →
**Get Tailscale certificate** → **Connect**. (macOS handles ECDSA certs natively
— no extra steps.) Details: [trusted HTTPS](tailscale-setup.md#trusted-https).

## 5. Operate from anywhere

From your remote device (Tailscale on, same account):

```
http://spe-amp.your-tailnet.ts.net:8080/      (or https:// if enabled)
```

For one-click access from another PC, use **SPE Remote Connect** —
see [operating from another PC or phone](connect-remote-and-phone.md).

---

## Keep it running

- Keep the app open and stop the Mac sleeping: **System Settings → Lock Screen /
  Battery → prevent sleeping when plugged in** (or use `caffeinate`).
- To auto-start: **System Settings → General → Login Items → +** and add
  `spe-remote-qt.app`.

## Troubleshooting

- **"can't be opened" / unidentified developer** — right-click → Open the first
  time (Step 1).
- **No serial port** — FTDI VCP driver, replug, ↻ rescan.
- **Can't reach remotely** — Tailscale running + signed in on both ends; try the
  `100.x` address from `tailscale status`.
- **HTTPS issues** — see [Tailscale troubleshooting](tailscale-setup.md#troubleshooting).
- **Bad readings / no amp connect** — re-check baud + model
  ([amplifier setup](amplifier-setup.md)).
