# Amplifier setup — 1K-FA vs 1.3K–2K-FA

The same app drives every SPE Expert amplifier. What differs between models is
the **baud rate**, the **wire protocol**, and a couple of UI details. You pick
the model once; everything else follows.

← Back to the [main guide](../README.md).

---

## Pick your model

| Your amplifier | Choose model | Baud rate |
|---|---|---|
| SPE Expert **1K-FA** | **1K-FA** | **9600** |
| SPE Expert **1.3K-FA** | **1.3K-FA** | **115200** |
| SPE Expert **1.5K-FA** | **1.5K-FA** | **115200** |
| SPE Expert **1.5K-FA TAURUS** | **1.5K-FA TAURUS** | **115200** |
| SPE Expert **2K-FA** | **2K-FA** | **115200** |

Pick your exact model from the **Amplifier model** dropdown on the **Settings**
page (browse to `http://<host>:8080/settings.html` — both the desktop app and
the headless daemon serve it). When you change the model, the app auto-snaps the
baud rate to that model's default, so you rarely need to touch baud manually.

## Physical connection

1. Connect the amplifier's **CAT / serial (USB)** port to the PC/Pi with the
   supplied cable.
2. Power the amplifier on.
3. On the amp, make sure its **CAT / remote** interface is enabled and set to
   the matching baud (see your amp's manual). The app speaks each amp's native
   protocol byte-for-byte, so no special amp-side mode is required beyond having
   CAT enabled.

## Selecting the serial port

In Connection settings, open the **Serial port** dropdown:

- The amp's USB-serial adapter is usually an **FTDI** chip — those entries are
  marked with a ★.
- If nothing sensible is listed, install the USB-serial driver, replug, and hit
  the **↻** rescan button.

Click **Connect**. Within a second or two the on-screen panel should start
mirroring the amplifier — power output, SWR, currents, band, antenna, etc.

## Model differences worth knowing

**1.3K-FA / 1.5K-FA / 1.5K-FA TAURUS / 2K-FA**
- 115200 baud, ASCII status protocol.
- The LCD shows the live operate screen (PA OUT / I PA / SWR bar graphs + the
  `IN | BAND | ANT | CAT | OUT | PW GAIN | TEMP` status row).

**1K-FA**
- 9600 baud, binary protocol.
- In addition to the operate screen, the UI **mirrors the amp's setup menus**
  (SET ANTENNA, SET CAT, BAUDRATE, MANUAL TUNE, BACKLIGHT, ALARM HISTORY, …) and
  the DISPLAY-key pages, with the selected item highlighted — navigate with the
  on-screen SET / ◄ / ► keys.

## Remote power on/off

The panel's **ON** and **OFF** buttons power the amplifier up and down remotely.
For this to work the amplifier must have **mains power** (its rear switch on) so
it can receive the power-on signal — the ON button can't help if the amp is
switched fully off at the back.

For the 1.3K–2K family, a **Power-on method** option on the Settings page
(**Auto / USB / RS-232**) selects how the ON button reaches the amp: **Auto**
fits the amp's built-in USB port, while **RS-232** is for a real serial port
wired to the amplifier's Remote_ON pin. Most users leave it on **Auto**.

---

## Safety first ⚠️

This software controls a **high-power RF amplifier**, including remotely. Before
operating remotely or unattended, make sure it is **safe and lawful**:

- Adequate cooling/ventilation and no fire risk if left running.
- RF-exposure and electrical safety handled at the station.
- You hold the appropriate licence and comply with all rules for remote /
  unattended operation in your country.

You use this software entirely at your own risk — see [EULA.txt](../EULA.txt).

## Troubleshooting

- **Connects but readings are wrong / garbled** — baud rate or model mismatch.
  Re-check the table above.
- **Won't connect at all** — wrong serial port, amp off, CAT disabled on the
  amp, or a bad cable. Try ↻ rescan and confirm the port in your OS.
- **Power-on does nothing remotely** — the amp is fully off at the rear (it must
  have mains power to accept a remote power-on), or, on a real RS-232 port, the
  **Power-on method** needs to be set to **RS-232** (see above).
