# The remote's Bluetooth protocol

Captured from a Mac with `blescan`, 22 Aug 2026. The remote is a Modern Forms
[F-RCBT-WT][inst] paired to a ceiling fan receiver.

## Conclusion first

**The remote broadcasts. It never connects to anything.** It advertises a
10-byte proprietary frame and the receiver simply listens.

That closes the iPhone route. iOS gives an app no way to put arbitrary bytes
into a BLE advertisement — `CBPeripheralManager` allows a local name and a list
of service UUIDs, and nothing else. No iOS app can reproduce these frames, no
matter how well the protocol is understood. See [what to do instead](#where-that-leaves-an-iphone-app).

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

## Where that leaves an iPhone app

Three options, best first:

1. **Use the fan's Wi-Fi**, if this receiver has any. Then none of the above
   matters and the app in this repo works as built. Unresolved — see
   [does your fan have Wi-Fi?](../PROTOCOL.md#does-your-fan-have-wi-fi).
2. **An ESP32 bridge.** It can transmit raw advertisements, which is exactly
   what iOS refuses to do. Have it replay this frame format and expose the
   Modern Forms `/mf` JSON API over HTTP, and the app in this repo talks to it
   **unmodified** — the bridge just looks like a Wi-Fi fan. This is the same
   approach [`ha-ble-adv`](https://github.com/NicoIIT/ha-ble-adv) takes for
   other fan brands.
3. **Keep using the remote.** Worth saying plainly.

## Still unknown

- Whether `03 02 01 07` is this remote's pairing identity, and whether the
  receiver accepts any remote presenting it.
- What the check byte actually computes.
- How the counter behaves at wrap, and how strictly the receiver enforces it.
- Whether the receiver advertises at all. It never appeared in any scan, so it
  most likely only listens — meaning there is nothing to connect to even if
  iOS could.

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
