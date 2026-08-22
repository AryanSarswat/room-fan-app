# The remote's Bluetooth protocol

Captured from a Mac with `blescan`, 22 Aug 2026. The remote is a Modern Forms
[F-RCBT-WT][inst] paired to a ceiling fan receiver.

## Conclusion first

**The remote broadcasts. It never connects to anything.** It advertises a
10-byte proprietary frame and the receiver simply listens.

**No iOS app can reproduce that frame.** Not a limitation of this project — a
platform rule, checked against primary sources in
[can an iPhone emit this?](#can-an-iphone-emit-this).

That is narrower than "an iPhone cannot control this fan". It rules out
*impersonating the remote*. Whether the receiver accepts a GATT connection is
[still open](#the-one-ios-only-path-left).

## The frame

    08 17 04 03 6A 03 02 01 07 21
    │     │  │  │  │           └── check byte
    │     │  │  │  └────────────── fixed: 03 02 01 07
    │     │  │  └───────────────── rolling counter, +1 per press
    │     │  └──────────────────── 03 for toggles, 00 for up/down
    │     └─────────────────────── button
    └───────────────────────────── fixed prefix

| Offset | Field | Status |
| --- | --- | --- |
| 0–1 | `08 17`, never varies | Not a Bluetooth SIG company ID: read little-endian it is 0x1708, above the highest ID ever assigned (0x110D). A proprietary marker |
| 2 | Button code, `01`–`07` | **Confirmed** for two codes, see below |
| 3 | `03` or `00` | **Confirmed** to partition the codes exactly, see below |
| 4 | Counter, `+1` per press | **Confirmed** over 38 consecutive frames |
| 5–8 | `03 02 01 07`, never varies | Almost certainly the pairing identity this remote was bound to. Unverified — it would take a second remote to prove |
| 9 | Check byte | Fits a formula but the mechanism is unexplained, see below |

### Byte 2 is the button

A controlled run: one button held for the first ~38 seconds, a different one
for the rest. Byte 2 changed at exactly that boundary and nowhere else.

    38.05s  08 17 04 03 80 03 02 01 07 3E     ← fan button
    39.24s  08 17 01 03 81 03 02 01 07 3D     ← light button
                  ^^    ^^             ^^

So `04` = fan on/off and `01` = light on/off, **confirmed by experiment**.

### Byte 3 splits the buttons into two kinds

Across every frame captured, byte 3 depends only on byte 2, with no overlap:

| Byte 3 | Button codes |
| --- | --- |
| `03` | `01`, `04`, `07` |
| `00` | `02`, `03`, `05`, `06` |

The F-RCBT has exactly seven buttons, and the manual splits them the same way:
three that toggle (light on/off, fan on/off, direction) and four that "press or
hold" to step a value (light up/down, fan up/down). Three codes carry `03`;
four carry `00`.

Since `01` and `04` are confirmed as the light and fan toggles, the third
toggle `07` is direction, and the step buttons pair off by neighbour:

| Code | Byte 3 | Function | Status |
| --- | --- | --- | --- |
| `01` | `03` | Light on/off | **Confirmed** |
| `02` | `00` | Light up or down | Inferred |
| `03` | `00` | Light down or up | Inferred |
| `04` | `03` | Fan on/off | **Confirmed** |
| `05` | `00` | Fan up or down | Inferred |
| `06` | `00` | Fan down or up | Inferred |
| `07` | `03` | Direction (Summer/Winter) | Inferred |

To finish the map, press each button once in a known order:

```bash
./.build/release/blescan watch <device-uuid> 60
```

### Byte 4 is a rolling counter

Over 38 consecutive frames it advanced by exactly one each time, `0x6A` through
`0x8F`, and did **not** reset when the button changed. That is anti-replay: the
receiver will presumably reject a frame whose counter it has already seen.

Anything that wants to impersonate this remote has to continue the sequence,
not start from zero — which is workable, since the current value can be read by
listening to the real remote once.

### Byte 9 is not a checksum I can explain

It fits this exactly, over all 38 frames and both button codes:

    byte9 == counter + counter/3 + byte2 - 112        (integer division)

It is not a sum or an XOR of the other bytes; both were tested and neither
matches. A slope of 4/3 against the counter is a strange thing for a check byte
to do, and 38 frames spanning only `0x6A`–`0x8F` is a narrow window. Treat the
formula as a curve fit, not as understanding. Frames spanning a counter wrap,
and frames from the other five button codes, would test it.

## Can an iPhone emit this?

No. Every route was checked against primary sources:

| Route | Verdict |
| --- | --- |
| `CBPeripheralManager.startAdvertising` with manufacturer data | **Blocked.** Apple's docs: "you may specify only the following two keys" — local name and service UUIDs — and "you receive an error if you specify any other keys." An Apple DTS engineer [confirms the same][dts] |
| iBeacon via `CLBeaconRegion.peripheralData` | **Blocked.** This *is* the one path where iOS emits AD type `0xFF`, which makes it the obvious thing to try — but the packet is a fixed layout with Apple's company ID hard-coded as `4C 00` followed by subtype `02 15`. It cannot carry `08 17` |
| Smuggle the bytes into a 128-bit service UUID | **Almost certainly blocked.** A 128-bit UUID is 16 arbitrary bytes, so the *payload* bytes can be put on air — but under AD type `0x07`, not `0xFF`. Any receiver that parses AD structures properly, which is the normal thing to do, will never look at them |
| Encode into the local name | Same problem: AD type `0x09` |
| A third-party library that works around it | **None exists.** `flutter_ble_peripheral` documents that on iOS "manufacturerData will be ignored" and works around it by using the service-UUID field — the same dead end |

The restriction is policy rather than hardware: the radio is capable, the API
will not expose it.

For contrast, **Android has no such restriction**. `AdvertiseData.Builder`
[`.addManufacturerData(int, byte[])`][android] writes AD type `0xFF` with the
company ID little-endian, so `addManufacturerData(0x1708, …)` produces exactly
the bytes above. Any Android phone can already speak this protocol.

## The one iOS-only path left

The receiver never advertised in any scan — but every scan was taken with the
fan already running and already paired. The remote's manual says pairing "must
be completed within three (3) minutes of turning the power ON to the fan
receiver", which implies the receiver behaves differently in that window.

**If it advertises as connectable while pairing, an iPhone can connect to it**
and none of the broadcast restriction matters.

Worth noting alongside this: Modern Forms' own app controls fans over **Wi-Fi
and their cloud**, not Bluetooth — setup asks for your Wi-Fi name and password.
So the vendor ships no Bluetooth app-control path either, which is weak
evidence against a usable GATT interface existing. Weak, not conclusive: the
app not using it does not mean it is absent.

The test costs nothing:

1. Kill power to the fan at the breaker for 10 seconds.
2. Restore power and immediately run `./.build/release/blescan 120`.
3. Diff the device list against a scan taken before the power cycle. Anything
   new and `connectable` is the receiver.
4. `./.build/release/blescan dump <uuid>` to walk its GATT tree.

## If that fails

Something other than the iPhone has to transmit. Any of these works — it is not
specifically an ESP32:

- **An Android phone**, per the API above. Cheapest if one is lying around.
- **A Linux host with a Bluetooth adapter.** `ha-ble-adv` supports this
  directly, no extra hardware.
- **An ESP32** running [`esphome-ble_adv_proxy`](https://github.com/NicoIIT/esphome-ble_adv_proxy).

Have any of them expose the Modern Forms `/mf` JSON API over HTTP and the app in
this repo drives it **unmodified** — the bridge just looks like a Wi-Fi fan.

[dts]: https://developer.apple.com/forums/thread/775252
[android]: https://developer.android.com/reference/android/bluetooth/le/AdvertiseData.Builder#addManufacturerData(int,%20byte[])

## Still unknown

- Whether `03 02 01 07` is this remote's pairing identity, and whether the
  receiver accepts any remote presenting it.
- What the check byte actually computes.
- How the counter behaves at wrap, and how strictly the receiver enforces it.
- Whether the receiver advertises during its three-minute pairing window. It
  never appeared in a scan of the fan in normal operation, but that window was
  never tested. This is the open question that decides whether an iPhone can
  reach it at all.

## Ruled out

Everything else in range resolved to unrelated household hardware by company
ID: Etekcity/Levoit `0x06D0`, GD Midea `0x06A8`, Qingdao Haier `0x0929`, Govee
`0x8802`/`0x8843`, Samsung `0x0075`, Nespresso, Apple `0x004C`, and a `dev132`
whose payload ends in ASCII `JLAISDK` (a JieLi audio SDK).

One device advertised under `0x0211`, **Telink Semiconductor** — the chipset
family behind most cheap BLE mesh lighting and fan controls — under several
peripheral UUIDs at once, which is how a mesh relay behaves. At -93 dBm with an
obvious `06 07 08 09 0A 0B 0C 0D 0E 0F` filler run in its payload, it is
probably a neighbour's mesh, not this fan.

[inst]: https://modernforms.com/images/products/INST_SHEET/F-RCBT_INSSHT.pdf
