# LocalDevVPN peer-IP correction — 2026-11-17

## Observed state

On the connected iPhone 16 Pro:

- LocalDevVPN 1.3.0 reported **Connected**.
- Its status page showed tunnel interface IP `10.7.1.1/32`.
- Its status page showed device/peer IP `10.7.0.1/32`.
- Wi-Fi was active (Wi-Fi indicator present).
- Locus Build 11's installed preferences contained `locus.targetDeviceIP = 10.7.1.1`.

## Root cause

Locus's `LocationEngine` passes `TunnelConfig.targetIP` to `tunnel_create_rppairing`, which opens the RemotePairing connection to that address on TCP port 49152.

The saved Locus value was the LocalDevVPN **interface** address, not its **device/peer** address. LocalDevVPN routes the peer address `10.7.0.1/32`; the correct target is therefore `10.7.0.1`.

The generic Locus error text ("Is LocalDevVPN connected on Wi-Fi?") was misleading in this case: the VPN was connected, but Locus was attempting the wrong destination IP.

## Device-side correction

- Backed up the original Locus preferences plist to the host's Downloads/Locus-Build11 folder.
- Stopped Locus before editing preferences.
- Changed only `locus.targetDeviceIP` from `10.7.1.1` to `10.7.0.1`.
- Preserved all other six preference keys.
- Pushed the plist back to the app container and pulled it again.
- Verified the device-side value is `10.7.0.1`.
- Relaunched Locus Build 11.
- The map status bar displayed **未模拟** ("Not spoofing") instead of **连接 LocalDevVPN**, confirming Locus now detects the active tunnel.

## Remaining acceptance test

A real map-pin teleport/restore test is still required to confirm that the TCP RemotePairing handshake and DVT location simulation now complete successfully. Do not mark the DVT path as fully verified until that test passes.

## Follow-up UX improvement

Clarify the Settings field as LocalDevVPN's **Device/Peer IP**, not its Tunnel Interface IP. Update the tunnel error message to mention the peer-IP setting instead of implying that Wi-Fi/VPN is necessarily disconnected.
