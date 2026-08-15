# Networking notes (batman-adv)

This file is the persistent record of the dual-homed mesh work. The Zig
process is still just a TCP HTTP server. batman-adv, 802.11s, and the
house LAN live in the OS.

## Topology we are building

```
  Phones / laptops
  (existing house Wi-Fi)
          │
   house router ──── Ethernet ──── server eth0
                                      │
                                 Zig :3491
                                 (one listen, 0.0.0.0)
                                      │
                                 server wlan0 = 802.11s
                                 batman-adv / bat0
                                      │
                     camera ←→ camera ←→ camera
                     (each is also 802.11s + batman-adv)
```

- People reach the server through the house LAN and the server’s Ethernet
  address. The house router is already their access point.
- Cameras never join the house SSID. Each camera is a **mesh point**, not
  an access point. Same radio mode as the server’s Wi-Fi NIC.
- Leave `net.ipv4.ip_forward=0` so Linux does not route `bat0` onto the
  house LAN.

A mesh point is not an AP. It does not advertise an SSID. Phones will not
see it. Cameras peer on a shared 802.11s mesh ID; batman-adv forwards
across hops. That is the repeater behavior.

Cameras must run Linux (Pi, similar, OpenWrt) so they can load
`batman-adv`. Store-bought STA cameras cannot be mesh repeaters.

## What this session changed in the repo

### `config.zap`

- Host is now `0.0.0.0` so one socket accepts both house-LAN users
  (`eth0`) and mesh cameras (`bat0`).
- New optional field `[ listen interface ]`. Left empty on purpose.
  Filling it with `bat0` would hide the server from the house LAN.
- `#` comments and blank lines are allowed.

### `src/config/root_config.zig`

- Parses `[ listen interface ]`. Empty value means “all interfaces.”
- Skips comments and blank lines.
- Unknown fields now return `error.UnknownConfigField` instead of hitting
  `unreachable`.
- A **missing** `config.zap` still writes `127.0.0.1` so a first-time run
  is not accidentally reachable.

### `src/threads/root_threads.zig`

- After `listen`, if an interface name is set, the NIC is resolved and
  `SO_BINDTODEVICE` is applied. A missing NIC fails startup.
- Listen failure now cancels the rest of the process (same as a bad
  address) so the other threads do not hang.

### `src/main.zig`

- Logs the configured host and whether the listen socket is restricted.
- Warns at startup that `Camera-Hash` is still an unverified free pass.

No AP, `hostapd`, `batctl`, or batman-adv logic was added to the binary.
That stays OS configuration.

## How to use the new bind

| `[ requested host address ]` | `[ listen interface ]` | Who can connect |
|---|---|---|
| `127.0.0.1` | empty | this machine only (dev) |
| `0.0.0.0` | empty | house LAN **and** `bat0` (this design) |
| `0.0.0.0` | `bat0` | mesh only (hides the server from the house) |
| `10.13.0.1` | empty | whatever NIC owns that address (`bat0` if you assigned it) |

People browse `http://<server-lan-ip>:3491/login`.
Cameras POST `http://<server-bat0-ip>:3491/archival/...`.

## What is still OS work (not in this binary)

Do these on the box, not by changing Zig:

1. Confirm cameras are Linux devices that can load `batman-adv`.
2. Plug the server into the house router. From a phone on house Wi-Fi,
   open `http://<server-lan-ip>:3491/login`.
3. On the server: 802.11s on `wlan0`, `modprobe batman-adv`,
   `batctl if add wlan0`, address `bat0` (example `10.13.0.1/24`).
   Confirm `ip_forward` is 0.
4. Same mesh ID, channel, and country on **one** nearby camera
   (`bat0` e.g. `10.13.0.10`). `batctl n` shows a neighbor.
   `ping 10.13.0.1` from the camera works. A house laptop must **not**
   ping `10.13.0.10`.
5. From that camera:
   `curl -H 'Camera-Hash: test' --data-binary @clip.ts http://10.13.0.1:3491/archival/cam01/clip.ts`
   File should land in `Archives/`.
6. Add a farther camera out of range of the server but in range of the
   first. `batctl tr 10.13.0.1` should go through the first camera.
   That is the repeater test.
7. Firewall: allow TCP `3491` on LAN `eth0` and on `bat0`. Do not publish
   it on the router’s WAN.
8. If large uploads stall, lower `bat0` MTU on every node (~1420–1468).

Suggested `bat0` numbering: server `.1`, cameras `.10`, `.11`, …

## What is still application work

These are not required to prove batman connectivity. They are required
before treating this as a security system.

- **Camera identity.** `request_gate.zig` still does
  `if (stream.camera_hash) |_| return true;`. Any TCP client that sends
  that header is treated as a camera. On `bat0` every mesh neighbor can
  upload or scrape. The path already sketched in `TODOs.md` is
  certificates. Do not revive the deleted per-IP camera log.
- **TLS.** batman-adv does not encrypt payloads. HTTP on the mesh is
  visible to every mesh member. House-LAN HTTP is visible on the LAN.
  Private CA / TLS is a later project.
- **Human-session hardening.** Cookies are `HttpOnly` + `SameSite=Strict`
  with no `Secure` flag (fine until TLS). Passwords still live in
  `config.zap`.
- **UI CDNs.** `static/HelloWorld.html` loads Tailwind + Google Fonts
  from the public internet. `static/player.html` loads `hls.js` from
  jsDelivr. House clients usually have uplink, so this is not blocking.
  Vendor those files under `static/` if you ever browse from a mesh node
  with no internet.
- **No discovery.** Cameras must be configured with the server’s `bat0`
  IP. This process does not run DHCP or mDNS.

## What we will not put in this binary

- `hostapd` / NetworkManager / `iw` / `batctl` wrappers
- Turning the HTTP process into an access point
- IP forwarding between `eth0` and `bat0`
- Putting cameras on the house SSID
