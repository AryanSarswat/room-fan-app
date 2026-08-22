# Modern Forms fan control protocol

Notes from working out how to control a Modern Forms ceiling fan without the
vendor app. Everything below has been exercised against a fan emulator; the
sections marked **unverified** still need real hardware.

## The short version

The Bluetooth remote and the Wi-Fi API are two front ends onto the same
receiver. The Wi-Fi API is fully documented and reachable from an iPhone; the
Bluetooth link is undocumented and may be impossible for an iPhone to speak at
all. So this project drives the fan over Wi-Fi.

## How the remote led to the Wi-Fi API

The [F-RCBT-WT operation instructions][inst] describe more than fan control.
Section 5 is **"Fan Wi-Fi Reset"**:

> NOTE: This function only resets the Wi-Fi settings. […] After the Wi-Fi
> resets, the fan will broadcast its factory set network name beginning with
> "ModernFormsFan."

and the factory-reset notes say a reset "will remove remote control(s), wall
control(s) **and Modern Forms app connections**."

So on Wi-Fi models the Bluetooth receiver and the Wi-Fi radio are one board, and
the remote is just one of several controllers paired to it (up to 10) alongside
wall controls and the app.

**This does not prove any particular receiver has Wi-Fi.** The F-RCBT ships
across the whole product line, so its manual documents functions that only
apply to some fans, and Modern Forms also sells Bluetooth-only receivers.
Settle which one you have first — see [Does your fan have Wi-Fi?](#does-your-fan-have-wi-fi).

The remote's documented capabilities also map one-for-one onto the Wi-Fi API,
which is good evidence they share a state machine:

| Remote button | Manual says | Wi-Fi API |
| --- | --- | --- |
| Light on/off | toggles the light | `lightOn` |
| Light up/down | "press or hold to increase/decrease the light level" | `lightBrightness` 1–100 |
| Fan on/off | toggles the fan | `fanOn` |
| Fan up/down | "your fan features 6 speeds" | `fanSpeed` 1–6 |
| Direction | Summer (CCW) / Winter (CW) | `fanDirection` `forward` / `reverse` |
| Breeze Mode | "varies the fan speed" | `wind`, `windSpeed` 1–3 |

## Does your fan have Wi-Fi?

Four states, in the order worth checking:

**1. On your network.** `mfctl scan` finds it. Nothing else to do.

**2. Has Wi-Fi, never provisioned.** It broadcasts a soft AP named
`ModernFormsFan_XXXXXX`. Look at your phone's Wi-Fi list — no tools needed.

**3. Has Wi-Fi, but still holds someone else's SSID.** Common in a house you
just moved into: the fan is hunting for a network that no longer exists, so it
is neither on your LAN nor broadcasting an AP. Section 5 of the [instruction
sheet][inst] fixes this: hold the two buttons it pictures for 10 seconds, and
the LED blinks green, the receiver beeps, and the fan starts broadcasting
`ModernFormsFan_XXXXXX`. Which two buttons is drawn as artwork rather than
written out, so check the sheet; it is one page. This resets Wi-Fi settings
only, and your remote stays paired.

**4. A Bluetooth-only receiver.** No AP, nothing on the network after a Wi-Fi
reset. The API below does not apply to your fan at all; see
[The Bluetooth question](#the-bluetooth-question).

Once the fan is broadcasting its own AP, join it (password `intelligence`) and
it answers on `10.10.10.1`:

```bash
swift run mfctl 10.10.10.1 status
```

That is the quickest way to confirm the protocol against real hardware, because
it needs no provisioning at all.

## The Wi-Fi API

One endpoint. `POST http://<fan-ip>/mf`, `Content-Type: application/json`.
The body is an object of commands; the response is the fan's full state as
JSON. Send `queryDynamicShadowData` with every request so a command doubles as
a state read.

```bash
curl -X POST http://192.168.1.50/mf \
  -H 'Content-Type: application/json' \
  -d '{"fanOn":true,"fanSpeed":4,"queryDynamicShadowData":true}'
```

```json
{"fanOn":true,"fanSpeed":4,"fanDirection":"forward","lightOn":false,
 "lightBrightness":50,"wind":false,"windSpeed":2,"awayModeEnabled":false,
 "adaptiveLearning":false,"fanTimer":0,"lightTimer":0}
```

### Keys

| Key | Type | Notes |
| --- | --- | --- |
| `fanOn` | bool | |
| `fanSpeed` | int | 1–6 |
| `fanDirection` | string | `forward` (Summer/CCW) or `reverse` (Winter/CW) |
| `lightOn` | bool | |
| `lightBrightness` | int | 1–100. `0` is not "off" — use `lightOn` |
| `wind` | bool | Breeze Mode. Absent entirely on receivers that lack it |
| `windSpeed` | int | 1–3 |
| `awayModeEnabled` | bool | |
| `adaptiveLearning` | bool | |
| `fanSleepTimer`, `lightSleepTimer` | int | Gen 1/2: absolute epoch seconds |
| `fanTimer`, `lightTimer` | int | Gen 3: seconds until off |
| `queryDynamicShadowData` | bool | ask for current state |
| `queryStaticShadowData` | bool | ask for model/firmware/MAC instead |
| `reboot`, `factoryReset`, `decommission` | bool | destructive; not used here |
| `rfPairModeActive`, `resetRfPairList` | bool | remote pairing list |
| `schedule` | string | |

Distinguish generations by which timer keys appear, not by model number.

### Two things worth knowing

`wind` missing and `wind` false are different. A receiver without Breeze Mode
never sends the key at all, so the app decodes it as `nil` and hides the
control rather than showing a toggle that does nothing.

Setting a speed does not imply the fan is on. This project sends `fanOn: true`
alongside `fanSpeed`, and `lightOn: true` alongside `lightBrightness`, to match
what the physical remote does when you press ▲ on a stopped fan. **Unverified**
on hardware — if your fan already behaves that way, the extra key is harmless.

### Finding the fan

There is no Bonjour/mDNS advertisement. Home Assistant discovers these by DHCP
hostname. This project sweeps the phone's own /24 and treats anything that
answers `/mf` with valid JSON as a fan.

### First-time provisioning

Only needed if the fan is not on your Wi-Fi yet, and not implemented here.
After a Wi-Fi reset the fan runs a soft AP `ModernFormsFan_XXXXXX` (last six
hex of its MAC) with password `intelligence`, at `10.10.10.1`. It accepts
`POST /config-write-uap` with `{"federatedIdentity","owner","deviceName",
"SSID","PASSWORD","DHCP","timezone"}`. Firmware `02.00.0026` reportedly
requires non-empty `federatedIdentity` and `owner` email addresses. Full
write-up: [colinbourassa][cb].

## The Bluetooth question

**No public reverse engineering of the Modern Forms BLE link exists.** Searches
across GitHub, Home Assistant forums and FCC filings turned up the Wi-Fi work
and nothing on Bluetooth. So this had to be reasoned about from first
principles, and the conclusion is that it is the wrong road for an iPhone app:

1. **iOS cannot transmit arbitrary BLE advertisements.** `CBPeripheralManager`
   lets an app advertise a local name and service UUIDs, and nothing else. No
   manufacturer-specific payload.
2. **Ceiling fan remotes are commonly broadcast-only.** They are coin-cell
   devices that never connect; they blast a short encoded advert that any
   paired receiver in range acts on. This is the whole premise of the
   [`ha-ble-adv`][bleadv] integration, which covers a long list of fan brands
   and needs an ESP32 precisely because a phone cannot do it.
3. If the receiver *does* accept GATT connections, an app can drive it — but
   the service and characteristic UUIDs, the command framing, and whatever
   pairing token the receiver expects would all still need a sniffer capture
   (nRF52840 + Sniffle, or Android's HCI snoop log).

Since the Wi-Fi API already exposes every documented remote function, the
Bluetooth route offers no extra capability for significant risk of being a dead
end.

### What a scan actually found

A [capture on 22 Aug 2026](../docs/ble-capture-2026-08-22.md) turned up a
strong, unnamed, **broadcast-only** device emitting ten-byte frames with a
fixed `08 17` prefix, a byte that varies over `01`–`07`, and a counter that
advances by exactly one per frame:

    08 17 04 03 5C 03 02 01 07 0E
             ^^ counter

A per-press rolling counter on a broadcast-only device is what point 2 above
predicts. `08 17` read as a little-endian company ID is 0x1708, above the
highest ID the Bluetooth SIG has assigned, so it is a proprietary marker rather
than a registered vendor. If this is the remote — the capture notes give the
one-command experiment that settles it — then the iPhone route is closed by
point 1, and a bridge is the only way in.

### Working it out for your fan

Two tools do the same job: the **Bluetooth Explorer** screen in the app, and
`blescan` on a Mac. `blescan` needs an embedded usage description or macOS
kills it on launch, so build it through the script and run it from Terminal.app
where the Bluetooth permission prompt can actually appear:

```bash
./Tools/build-blescan.sh && ./.build/release/blescan 20
```

Press buttons on the physical remote while either one is scanning, and read the
result:

- **A device appears, marked "broadcast only", whose manufacturer-data hex
  changes on each button press.** That is the remote broadcasting commands.
  An iPhone cannot reproduce this. Wi-Fi or an ESP32 bridge are the options.
- **A connectable device appears** (likely the receiver). Tap it. The explorer
  dumps every service and characteristic with its properties, reads the
  readable ones, and subscribes to the notifying ones. A vendor service with a
  writable characteristic is the thing worth chasing — share the log and it can
  be probed further.
- **Nothing appears on a button press.** The link may not be BLE advertising at
  all, or the remote's transmit window is too short to catch reliably.

## References

- [F-RCBT-WT operation instructions (PDF)][inst] — the manual that revealed the Wi-Fi reset
- [Modern Forms Bluetooth Remote Control product page][prod]
- [colinbourassa — Modern Forms fan IP control][cb] — soft-AP provisioning
- [`aiomodernforms`][aio] — the Python client behind Home Assistant; the command set here matches it, and its `mock_fan` emulator was used to test this project
- [Home Assistant Modern Forms integration][ha]
- [Home Assistant community thread][thread] — original reverse engineering
- [`ha-ble-adv`][bleadv] — broadcast-style BLE ceiling fan remotes, and why they need an ESP32

[inst]: https://modernforms.com/images/products/INST_SHEET/F-RCBT_INSSHT.pdf
[prod]: https://modernforms.com/product/bluetooth-remote-control/
[cb]: https://colinbourassa.github.io/software/modernforms/
[aio]: https://github.com/wonderslug/aiomodernforms
[ha]: https://www.home-assistant.io/integrations/modern_forms/
[thread]: https://community.home-assistant.io/t/modern-forms-smart-fans-integration/109318
[bleadv]: https://github.com/NicoIIT/ha-ble-adv
