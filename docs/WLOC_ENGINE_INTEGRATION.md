# WLOC-style engine integration: feasibility and implementation boundary

Status: engineering investigation; no Packet Tunnel engine is shipped by this change.

## Existing engine

Locus currently uses Apple's developer location simulation (DVT) through the MIT-licensed `idevice` FFI. The supported operation in the linked API is `simulateLocationWithLatitude:longitude:`; the current wrapper therefore sets coordinates only. Keep this engine as the default and preserve its existing pairing, route, joystick, restore, and reconnect behavior.

## WLOC-style network-location path

The WLOC project describes a separate iOS Packet Tunnel + on-device HTTPS interception path that rewrites Apple's `/clls/wloc` Wi-Fi/cell-location response. This is not an extension of the DVT call and must not be represented as one. It also does not provide a general iOS API for setting GPS hardware measurements.

A future implementation must be a separately selectable, opt-in test engine, with:
- a distinct Network Extension target and Packet Tunnel provider;
- an explicit local configuration and lifecycle state machine;
- local-only certificate generation/storage and a user-driven trust/install flow;
- bounded, host- and path-scoped processing with strict pass-through for unrelated traffic;
- deterministic protobuf fixtures and tests for malformed, compressed, unknown-field, and version-mismatched payloads;
- a clear one-tap stop/restore path and visible indicator while the tunnel is active;
- no claim that the engine controls GPS accuracy or the accuracy another app will receive.

Do not silently start the tunnel, install/trust a certificate, or replace the DVT engine. Never intercept unrelated hosts or traffic.

## Licensing boundary

This repository is MIT-licensed. The WLOC repository and the two referenced `ios-location-spoofer` implementations currently declare AGPL-3.0. Do not copy or link their implementation into this repository unless the owner explicitly chooses the corresponding licensing obligations. Prefer an independently implemented component using permissively licensed dependencies, with provenance recorded for each dependency.

The `idevice` library currently used by Locus declares MIT.

## Signing and device prerequisites

Packet Tunnel distribution requires the Network Extensions entitlement and matching provisioning. The app and extension also need a shared App Group for local configuration/certificate handoff. A successful unsigned CI build is not proof that the extension can be activated on a phone. Device validation requires an eligible Apple Developer team/profile with the Packet Tunnel capability and a macOS/Xcode signing environment.

## Acceptance gates before implementation can be called complete

1. The existing DVT path still builds and passes its current coordinate tests.
2. The extension target builds independently and has the correct extension point and entitlements.
3. Unrelated HTTP(S) requests are passed through unchanged.
4. The location-response parser has fixture-based tests and fails closed (pass-through) on unknown formats.
5. Start/stop, app termination, tunnel interruption, and certificate removal are tested on a physical iPhone.
6. The UI labels this as a network-location test path and clearly distinguishes it from DVT/GPS simulation.
7. The user explicitly approves the signing/account setup before any certificate trust or VPN profile is installed.

## Current blocker

The user's Windows Desktop Commander device is currently offline, so the connected iPhone cannot be inspected or operated through that computer session. Code review and CI work can continue; physical-device verification must wait until the desktop connection is online.
