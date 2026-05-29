# Tailscale setup & trusted HTTPS

[Tailscale](https://tailscale.com/) is a free, private mesh VPN. It builds an
encrypted (WireGuard) tunnel directly between *your own* devices, so you can
reach the amp's control panel from anywhere — **without** port-forwarding,
without exposing anything to the public internet, and without revealing your
home IP. This page covers the one-time account setup that every OS guide refers
back to.

← Back to the [main guide](../README.md).

---

## 1. Create a free Tailscale account

1. Go to **[tailscale.com](https://tailscale.com/)** → **Get started**.
2. Sign in with Google / Microsoft / GitHub / email. The free **Personal** plan
   is plenty (up to 100 devices).

You'll add devices to this one account — that shared account *is* your private
network ("tailnet").

## 2. Install Tailscale on BOTH ends

You need Tailscale on:

- the **PC/Pi at the amp** (the server), **and**
- **every device you'll operate from** (laptop, phone, shack PC).

Install links: **[tailscale.com/download](https://tailscale.com/download)**.
The per-OS guides ([Windows](install-windows.md), [macOS](install-macos.md),
[Linux](install-linux.md), [Raspberry Pi](install-raspberry-pi.md)) show the
exact commands. Sign every device in to the **same account**.

## 3. Turn on MagicDNS (do this once)

MagicDNS gives each device a friendly name like `your-amp.tailXXXX.ts.net`
instead of a bare `100.x.y.z` address.

1. Open the **[admin console → DNS](https://login.tailscale.com/admin/dns)**.
2. Enable **MagicDNS**.

## 4. Name the amp's machine

In the **[admin console → Machines](https://login.tailscale.com/admin/machines)**
you'll see your devices. Note (or rename) the **amp PC/Pi's** name — that's what
you'll type to reach it, e.g. `spe-amp`. Renaming to something memorable now
makes the URL nicer later:

```
http://spe-amp.tailXXXX.ts.net:8080/
```

> Find your tailnet's full name (`tailXXXX.ts.net`) at the top of the admin
> console, or run `tailscale status` on any device.

## 5. Reach the amp

With Tailscale running on both ends, open a browser on your remote device:

```
http://<amp-machine-name>.<your-tailnet>.ts.net:8080/
```

That's the live control panel. Done — it's already private and encrypted by the
tunnel.

---

## Trusted HTTPS

The Tailscale tunnel already encrypts everything. If you *also* want the browser
**padlock** (a second, independent layer of TLS, and no "Not secure" label),
turn on HTTPS. It uses a real, browser-trusted certificate issued by Tailscale.

### One-time: allow Tailscale to issue certificates

In the **[admin console → DNS](https://login.tailscale.com/admin/dns)**, enable
**HTTPS Certificates** (just below MagicDNS). You must be the tailnet
owner/admin.

### Then turn it on — one click

- **Desktop app (Windows / macOS / Linux):** open the cog → **Connection
  Settings** → **Web server security** → tick **Serve over HTTPS** → click
  **Get Tailscale certificate**. It fetches the cert and switches to HTTPS.
- **Headless Raspberry Pi:** open **Settings** in the browser
  (`http://<host>:8080/settings.html`) → **Web server security** → **Get
  Tailscale certificate**. The daemon switches itself to HTTPS and the page
  reloads over `https://`.

Then browse:

```
https://<amp-machine-name>.<your-tailnet>.ts.net:8080/
```

> **Use the machine name, not the `100.x` IP** — the certificate is issued for
> the name, so the IP would show a name-mismatch warning.

Certificates auto-handle renewal when fetched through the app. (Tailscale certs
last ~90 days; just click **Get/Renew Tailscale certificate** again if ever
needed.)

---

## Troubleshooting

- **"tailscale cert failed: …account does not support getting TLS certs"** —
  enable **HTTPS Certificates** + **MagicDNS** in the admin console (steps
  above), then retry. You must be the tailnet owner/admin.
- **Name won't resolve** — make sure MagicDNS is on and Tailscale is running on
  the device you're browsing from.
- **Page loads but controls are dead over HTTPS** — use the app's built-in HTTPS
  (above), *not* `tailscale serve`; the latter only proxies the page, not the
  control channel.
