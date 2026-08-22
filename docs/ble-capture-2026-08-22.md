# Bluetooth capture, 22 Aug 2026

Two 20-second `blescan` runs from a Mac in the same room as the fan, with
remote buttons pressed during both. 117 and 84 devices respectively — a dense
apartment RF environment, so most of what follows is ruling things out.

## The candidate

One device stands out: **unnamed, broadcast-only, and by far the strongest
signal in the room** (-29 dBm on the first run, -43 dBm on the second — within
a metre or two of the Mac, consistent with a handheld remote).

    id 8B61D3D4-0BD8-6C95-CA9D-6D9286E15897

Every payload it emitted, in order across both runs:

    08 17 01 03 59 03 02 01 07 07
    08 17 06 00 5A 03 02 01 07 0B
    08 17 05 00 5B 03 02 01 07 0B
    08 17 04 03 5C 03 02 01 07 0E
    08 17 04 03 5D 03 02 01 07 10
    08 17 04 03 5E 03 02 01 07 11
    08 17 05 00 5F 03 02 01 07 10
    08 17 06 00 60 03 02 01 07 13
    ----- gap between runs -----
    08 17 05 00 62 03 02 01 07 14
    08 17 07 03 63 03 02 01 07 1B
    08 17 01 03 64 03 02 01 07 16
    08 17 01 03 65 03 02 01 07 17
    08 17 03 00 66 03 02 01 07 18
    08 17 04 03 67 03 02 01 07 1D
    08 17 02 00 68 03 02 01 07 19

### What the bytes look like

| Offset | Observed | Reading (**hypothesis**) |
| --- | --- | --- |
| 0–1 | `08 17`, never varies | Prefix. As a little-endian company ID this is 0x1708, which is **above the highest ID the Bluetooth SIG has assigned** (0x110D), so it is not a real company identifier — just a proprietary marker |
| 2 | `01`–`07` | Button or command code |
| 3 | only ever `00` or `03` | A flag or parameter |
| 4 | `59 5A 5B 5C 5D 5E 5F 60` then `62`…`68` | **Monotonic counter, +1 per payload.** Only advanced 2 between runs |
| 5–8 | `03 02 01 07`, never varies | Fixed — a device or pairing identifier |
| 9 | varies, no obvious pattern | Checksum over the rest |

The counter is the interesting part. It increments by exactly one per emission
and does not free-run between scans, which is what a **rolling anti-replay
counter on a keypress** looks like, not periodic telemetry.

### What this implies

If this is the remote, then **the remote broadcasts its commands** — it never
connects to anything. iOS will not let an app put arbitrary bytes in an
advertisement, so an iPhone cannot reproduce these frames, and no amount of
app-side work changes that. Controlling this fan from an iPhone would need
either the fan's Wi-Fi side or a small always-on bridge (ESP32) that can
transmit raw adverts, as [`ha-ble-adv`](https://github.com/NicoIIT/ha-ble-adv)
does for other fan brands.

**This is not yet confirmed.** See the experiment below.

## Confirming it

Watch that one device and press a *single* button repeatedly:

```bash
./.build/release/blescan watch 8B61D3D4-0BD8-6C95-CA9D-6D9286E15897 60
```

- **Byte 4 advances by one per press and byte 2 holds steady** → confirmed. It
  is the remote, byte 2 is the command, and the iPhone route is closed.
- **Nothing appears while pressing** → wrong device; it is some other beacon
  that happened to be nearby.

Then press each button once in a known order to map byte 2 to functions.

## Ruled out

Everything else in range resolved to unrelated household hardware, identified
by the company ID in its manufacturer data:

| Device | Company ID | Vendor |
| --- | --- | --- |
| `Core200S`, `classic300s` | 0x06D0 | Etekcity / Levoit |
| `net` | 0x06A8 | GD Midea |
| `GRF400PV1SS` | 0x0929 | Qingdao Haier |
| `Govee_*`, `GBK_H6159` | 0x8802/3, 0x8843 | Govee |
| `75" QLED`, `43" Crystal UHD` | 0x0075 | Samsung |
| `Vertuo_*` | — | Nespresso |
| `dev132` | — | payload ends in ASCII `JLAISDK`, a JieLi audio SDK |
| Apple devices | 0x004C | phone, watch, AirPods |

One other device is worth a second look if the candidate above does not pan
out: **`6E4F6138F09E8172`**, which advertises under company ID **0x0211,
Telink Semiconductor** — the chipset family behind most cheap BLE mesh
lighting and fan controls. It appeared under several peripheral UUIDs at once,
both connectable and broadcast-only, which is how a mesh relay behaves. It was
weak (-93 dBm) and its payloads carry an obvious `06 07 08 09 0A 0B 0C 0D 0E
0F` filler run, so it is probably a neighbour's mesh rather than this fan.

## Not found

No Modern Forms or WAC device appeared, and no soft AP named
`ModernFormsFan_XXXXXX`. Either the receiver only advertises while in pairing
mode, or it never advertises at all and simply listens for the remote's
broadcasts — which is the usual arrangement for this class of hardware.
