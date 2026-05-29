# Operating from another PC or a phone

Once the amp end is set up (an [OS guide](../README.md#per-os-install--setup-guides)
done) and on Tailscale, here's how to reach it from wherever you're operating.

← Back to the [main guide](../README.md).

> The golden rule for **every** method: the device you operate from must have
> **Tailscale installed and signed in to the same account** as the amp. That's
> what makes the private tunnel.

---

## Any device — just a browser

With Tailscale running, open:

```
http://spe-amp.your-tailnet.ts.net:8080/        (or https:// if you enabled it)
```

(Use **your** amp machine's Tailscale name.) That's the full panel — power,
input, antenna, tune, levels, live meters — same as sitting in front of it.

---

## From another PC — one-click with SPE Remote Connect

The Windows/macOS/Linux download includes a small companion app, **SPE Remote
Connect**, for the PC you operate *from*. It removes the need to remember names
or URLs:

1. Install it on the remote PC (it's in the same download as the main app; on
   Windows the installer adds an *SPE Remote Connect* shortcut).
2. Launch it. If Tailscale isn't set up yet it offers an **Install Tailscale**
   button; otherwise click **Connect** — it brings the tunnel up (signing you
   in if needed).
3. In the **Home server** box, set the amp's **Tailscale name** (e.g. `spe-amp`)
   and the port (8080). Tick **Use HTTPS** if you enabled HTTPS at the amp.
4. Click **Open SPE Remote** — it launches the control panel in your browser.

It just drives Tailscale + opens the right URL for you; it doesn't need the amp
plugged into this PC.

---

## From a phone or tablet (Android / iOS)

1. Install the official **Tailscale** app (Play Store / App Store) and sign in
   to the **same account**.
2. Open the amp's URL in your browser:
   ```
   http://spe-amp.your-tailnet.ts.net:8080/
   ```
3. **Add it to your home screen** for an app-like icon:
   - **Android (Chrome):** ⋮ menu → **Add to Home screen**.
   - **iPhone/iPad (Safari):** Share → **Add to Home Screen**.

   It then launches full-screen, like a native app.

> The full installable-app (PWA) experience needs an **HTTPS** address — turn on
> [trusted HTTPS](tailscale-setup.md#trusted-https) at the amp and use the
> `https://…` URL. Over plain `http://` you still get a working home-screen
> shortcut.

---

## Tips

- **Bookmark** the URL (or pin the home-screen icon) so you're one tap from the
  panel.
- If the page loads but controls don't respond over HTTPS, you're likely using
  `tailscale serve` — don't; use the app's built-in HTTPS instead
  ([why](tailscale-setup.md#troubleshooting)).
- Nothing here is exposed to the public internet — only your signed-in devices
  can reach the amp.
