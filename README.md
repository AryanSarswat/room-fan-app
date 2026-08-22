# Room Fan

A minimal iPhone app that replaces the Bluetooth remote for a
[Modern Forms][prod] ceiling fan — light, brightness, fan power, six speeds,
direction and Breeze Mode.

It talks to the fan over **Wi-Fi**, not Bluetooth. That turned out to be the
only route an iPhone can actually take, and it loses nothing: see
[PROTOCOL.md](PROTOCOL.md) for how that was established and the full command
reference.

<img src="docs/control-screen.png" width="300" alt="The control screen">

## What's here

| | |
| --- | --- |
| [`Sources/ModernFormsKit`](Sources/ModernFormsKit) | The protocol: state model, commands, HTTP client, subnet discovery |
| [`Sources/mfctl`](Sources/mfctl) | A CLI to poke the fan from a Mac |
| [`App/RoomFan`](App/RoomFan) | The SwiftUI app, plus a Bluetooth Explorer for further digging |
| [`PROTOCOL.md`](PROTOCOL.md) | The reverse-engineering write-up and API reference |

## Try it against your fan

Find the fan and drive it from the command line first — quicker than
installing anything:

```bash
swift run mfctl scan
```

```bash
swift run mfctl 192.168.1.50 speed 3
```

`scan`, `status`, `fan on|off`, `speed 1-6`, `forward|reverse`,
`light on|off`, `brightness 1-100`, `breeze on|off`. An address may carry a
port (`192.168.1.50:8088`).

Or with no Swift at all:

```bash
curl -X POST http://192.168.1.50/mf -H 'Content-Type: application/json' -d '{"fanOn":true,"fanSpeed":4,"queryDynamicShadowData":true}'
```

## Build the app

Needs [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
— the `.xcodeproj` is generated, not committed.

```bash
cd App && xcodegen generate && open RoomFan.xcodeproj
```

On first launch, tap **Choose a fan** → **Scan this network**, or type the
address in. It is stored and the app reconnects on its own.

## How this was worked out

The fan came with a [Bluetooth remote][prod], so Bluetooth looked like the
obvious target. It was the wrong one, and finding that out cheaply was most of
the work.

**1. Look for prior art.** Nobody has published anything on the Modern Forms
BLE link — not on GitHub, the Home Assistant forums, or in FCC filings. The
Wi-Fi side, by contrast, is thoroughly documented: there is a [Home Assistant
integration][ha], a [Python client][aio], and a [write-up of the provisioning
protocol][cb].

**2. Read the remote's own manual.** The [F-RCBT-WT instruction sheet][inst]
has a section titled *"Fan Wi-Fi Reset"*, and its factory-reset warning
mentions removing "Modern Forms app connections". So the Bluetooth receiver in
the fan is the same board that joins your Wi-Fi — the remote is just one of
several controllers paired to it. Every function the remote has maps one-to-one
onto a Wi-Fi API key.

**3. Check whether an iPhone could speak Bluetooth anyway.** It probably
cannot. iOS will not let an app transmit arbitrary BLE advertisements, and
ceiling fan remotes are typically broadcast-only devices — which is why
[`ha-ble-adv`][bleadv] needs an ESP32 rather than a phone. Chasing it would
have meant a hardware sniffer for capability the Wi-Fi API already provides.

**4. Build on Wi-Fi, and ship the Bluetooth instrument anyway.** The app has a
Bluetooth Explorer screen that dumps nearby advertisements (including
manufacturer-data hex, which changes per button press on a broadcast remote)
and walks the GATT tree of anything connectable. If you want to settle the
question for your own fan, that screen is the tool —
[PROTOCOL.md](PROTOCOL.md#working-it-out-for-your-fan) explains how to read it.

## What's verified, and what isn't

Verified: the protocol implementation is exercised end to end against the
`mock_fan` emulator that ships with [`aiomodernforms`][aio] — every command
from both the CLI and the app's UI, plus the state the app renders. 13 unit
tests cover command encoding, clamping, state decoding and address parsing.

```bash
swift test
```

To run the emulator yourself:

```bash
git clone https://github.com/wonderslug/aiomodernforms && cd aiomodernforms && pip install aiohttp backoff && python -m mock_fan --generation gen3 --breeze --port 8088
```

**Not verified against real hardware.** Nobody has yet pointed this at an
actual fan. The emulator implements the same wire protocol as the Home
Assistant client, so the risk is low, but two things are genuinely assumptions:

- That setting `fanSpeed` should also send `fanOn: true` (and likewise for
  brightness), matching what the remote does on a stopped fan.
- That your receiver is on Wi-Fi at all. If your fan predates 2021 or is an RF
  model rather than Bluetooth, none of this applies.

The Bluetooth Explorer is diagnostics only — it reads, it does not control.

## References

- [Modern Forms Bluetooth Remote Control (F-RCBT-WT)][prod] · [instruction sheet (PDF)][inst]
- [colinbourassa — Modern Forms fan IP control][cb]
- [`aiomodernforms`][aio] · [Home Assistant integration][ha] · [community thread][thread]
- [`ha-ble-adv`][bleadv] — broadcast-style BLE fan remotes

[prod]: https://modernforms.com/product/bluetooth-remote-control/
[inst]: https://modernforms.com/images/products/INST_SHEET/F-RCBT_INSSHT.pdf
[cb]: https://colinbourassa.github.io/software/modernforms/
[aio]: https://github.com/wonderslug/aiomodernforms
[ha]: https://www.home-assistant.io/integrations/modern_forms/
[thread]: https://community.home-assistant.io/t/modern-forms-smart-fans-integration/109318
[bleadv]: https://github.com/NicoIIT/ha-ble-adv
