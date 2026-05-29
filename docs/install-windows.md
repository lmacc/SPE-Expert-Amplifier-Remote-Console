# Windows — install & set up

Full walkthrough: install the app, connect your SPE Expert amp, set up Tailscale,
and reach it from anywhere (with HTTPS). ~15 minutes.

← Back to the [main guide](../README.md).

---

## What you'll end up with

The **SPE Expert Amplifier Remote** app running on this Windows PC (plugged into
the amp by USB), reachable from your other devices over Tailscale at
`https://your-amp.your-tailnet.ts.net:8080/`.

---

## 1. Install the app

1. Go to the **[Releases page](../../releases/latest)**.
2. Download **`spe-remote-qt-<version>-windows-x64-setup.exe`**.
3. Run it. Accept the licence (the EULA), keep the defaults, and finish.
   - This installs two shortcuts: **SPE Expert Amplifier Remote** (the app you
     run at the amp) and **SPE Remote Connect** (for operating *from* another
     PC — you don't need that one here).
   - Prefer no installer? Download the `...-windows-x64.zip` instead and run
     `spe-remote-qt.exe` from the extracted folder.

> Windows SmartScreen may warn about an unrecognised app (the build isn't code-
> signed). Click **More info → Run anyway**.

## 2. Connect the amplifier

1. Plug the amp into the PC with the USB cable and power the amp on.
2. Launch **SPE Expert Amplifier Remote**.
3. Click the **cog** (⚙) on the chassis → **Connection settings**.
4. Set:
   - **Serial port** — pick the amp's port (FTDI devices are starred ★). Hit ↻
     to rescan if it's not listed.
   - **Baud rate** — **9600** for the **1K-FA**, **115200** for the
     **1.3K / 1.5K / 2K-FA**.
   - **Amplifier model** — choose **1K-FA** or **1.3K–2K-FA** (see
     [amplifier setup](amplifier-setup.md) for the differences).
5. Click **Connect**. The status line should show *Connected*, and the on-screen
   panel should start mirroring the amp.

Locally you can already use it at **`http://localhost:8080/`** in a browser.

## 3. Install Tailscale (so you can reach it remotely)

1. Download from **[tailscale.com/download/windows](https://tailscale.com/download/windows)**
   and install.
2. Sign in (the system-tray Tailscale icon → **Log in**) to your Tailscale
   account — see **[Tailscale setup](tailscale-setup.md)** if you haven't made
   one yet.
3. Do the same on the device you'll operate *from*, signed in to the **same
   account**.
4. One-time, in the [admin console](https://login.tailscale.com/admin/dns):
   enable **MagicDNS** (and **HTTPS Certificates** if you want the padlock).
5. Note this PC's name in the
   [Machines](https://login.tailscale.com/admin/machines) list — e.g. `spe-amp`.

## 4. (Optional) Turn on HTTPS

In **Connection settings → Web server security**: tick **Serve over HTTPS** →
**Get Tailscale certificate** → **Connect**. The status line shows **· HTTPS**.
Details: [trusted HTTPS](tailscale-setup.md#trusted-https).

## 5. Operate from anywhere

On your remote laptop/phone (Tailscale running, same account), open:

```
http://spe-amp.your-tailnet.ts.net:8080/      (or https:// if you enabled it)
```

You get the full control panel — power, input, antenna, tune, levels, live
meters. For a one-click experience on a remote **PC**, use the bundled **SPE
Remote Connect** app — see
[operating from another PC or phone](connect-remote-and-phone.md).

---

## Keep it running

- The app must stay open (and the PC awake) for remote access. Disable sleep on
  this PC: **Settings → System → Power → Screen and sleep → Sleep: Never** (when
  plugged in).
- To launch automatically at login, put a shortcut to `spe-remote-qt.exe` (add
  `--autostart` so it connects on launch) in your Startup folder
  (`Win+R` → `shell:startup`).

## Troubleshooting

- **No serial port listed** — install the amp's USB driver (FTDI), replug, hit ↻.
- **Can't reach it remotely** — confirm Tailscale is running and signed in on
  *both* devices; try the `100.x` address from `tailscale status`.
- **HTTPS / certificate errors** — see
  [Tailscale troubleshooting](tailscale-setup.md#troubleshooting).
- **Wrong readings / won't connect to amp** — re-check baud + model match your
  amplifier ([amplifier setup](amplifier-setup.md)).
