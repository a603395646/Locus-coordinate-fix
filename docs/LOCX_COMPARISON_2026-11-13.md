# WLOC / loc-x compatibility comparison (2026-11-13)

This note records a source-level comparison for the Locus iOS 26.2.1 / trust asset 1014 investigation. It is an engineering assessment, not a claim that WLOC MITM works on this device.

## Executive decision

**Do not integrate a WLOC MITM engine or trust-database writer into the current Locus build for iPhone 16 Pro / iOS 26.2.1 / trust asset 1014.** The reviewed projects still depend on the same Apple location-service TLS interception path, or on privileged modification of the protected trustd pinning database. None demonstrates a supported, non-TrollStore recovery on iOS 26.2.1 with asset 1014.

Keep the existing DVT developer-location engine as Locus's default. Treat a WLOC-style network-location engine as a separate, opt-in research path only if a supported certificate-validation route becomes available.

## Locus baseline

The current `feat/wloc-native-core` investigation branch records Build 11 (1.0.5/11) as installed and launchable on the iPhone 16 Pro / iOS 26.2.1. The current engine in `Locus/Engine/LocationEngine.swift` calls the idevice DVT location-simulation API over the developer tunnel. It accepts latitude and longitude; it is not a WLOC response rewriter.

The branch's `project.yml` defines one iOS application target. The app entitlements do not include a Packet Tunnel Network Extension entitlement or an App Group for an embedded provider. The current workflow uses the separately installed LocalDevVPN loopback tunnel for DVT transport. Build 11's controlled DVT teleport/restore still requires a physical-device acceptance test; the investigation note also records a map status-bar refresh discrepancy while Settings reports LocalDevVPN connected.

The existing WLOC integration boundary is documented in `docs/WLOC_ENGINE_INTEGRATION.md`: keep DVT behavior intact; do not silently install certificates, start a tunnel, or claim that a network-location response changes GPS hardware measurements.

## Repository comparison

### 1. gitfengxx/loc-x

Reviewed the current README and source files including `Sources/Tunnel.m`, `Sources/Proxy.m`, `Sources/LocalControl.m`, `Sources/VPNLifecycle.h`, `Sources/TargetSettings.h`, and `Sources/GlobalSearch.m`.

- The latest reviewed source commit updates the app to 0.3.12 / build 17. Its README's device validation remains iPhone 7 / iOS 15.8.5 with TrollStore; it does not claim iOS 26.2.1 / asset 1014 compatibility.
- It embeds a Packet Tunnel provider and a local TLS interception proxy. The tunnel uses host-scoped proxy matching; the proxy allowlists a small set of Apple / AutoNavi hosts and rewrites only a successful `/clls/wloc` response.
- The local app-to-extension control channel is a useful design reference: loopback-only binding, HMAC authentication, nonce/time-window checks, monotonically increasing command sequence, bounded request sizes, and a separate status response.
- Its request handler is deliberately narrow: CONNECT to port 443 only, HTTP/1.1-style request parsing, Content-Length bodies only, no Transfer-Encoding, and a 2 MiB body/response ceiling. It is not a general-purpose transparent proxy.
- Its README explicitly says the app does not replace GPS and does not guarantee that every app adopts the network result.
- The repository root did not expose a general LICENSE file during this review. The vendored WLOC map assets include an AGPL-3.0 notice. Do not copy its implementation into the MIT-licensed Locus repository without confirming the applicable upstream license and obtaining an explicit licensing decision.

**Locus reuse decision:** borrow architecture ideas only (state machine, authenticated loopback control, strict allowlists, bounded parsing, observable request/patch counters). Do not transplant the proxy or WLOC script. The Packet Tunnel target would also require the appropriate Network Extension entitlement, provisioning, and shared App Group; the current Locus target does not have these.

### 2. xweiba/location-spoofer v1.0.9

Reviewed the README, Chinese README, build configuration, Go module, third-party module notes, and LICENSE.

- The project is AGPL-3.0.
- App Mode embeds a Go proxy and asks the user to set a manual HTTP proxy on the current Wi-Fi. It avoids a Network Extension, but still requires installing/trusting a local CA and decrypting the Apple location-service traffic.
- Third-party Proxy Mode delegates MITM, certificate, and VPN handling to the selected proxy client. It still relies on the same Apple location-service interception.
- The project compatibility notice explicitly lists reports for iOS 26.2.1 and says it has no verified general recovery method. It warns that a successful generic CA check does not prove the Apple location endpoint accepts the certificate.
- App Mode is Wi-Fi-only. It does not provide a cellular route.

**Locus reuse decision:** no engine code should be ported. Its separation of configuration state, environment checks, and diagnostic reporting is a useful product-design reference, but it does not solve trust asset 1014 and its AGPL-3.0 license is incompatible with casual copying into this MIT project.

### 3. spirit-n/WLOCRules

The reviewed README describes a TrollStore tool that checks, backs up, removes, and restores the matching `gs-loc` / `gs-loc-cn` pinning rule. It requires content 131 / schema 3. The stated real-device test is iPhone 13 Pro Max / iOS 15.7 / trust asset 33.

This is a privileged trust-database modification, not an ordinary certificate installation or proxy setting. It is not a usable path for the user's iOS 26.2.1 device without the required privileged installation environment. The repository does not state a clear license in the reviewed README; do not copy its code.

### 4. DKJone/OSPinOverload 1.0.2

The reviewed README identifies build 10 and requires TrollStore. Its documented real-device validation is iPhone 11 / iOS 15.7.1. It has stronger safety engineering than the earlier one-off scripts (independent backup, preflight, transactional single-row modification, read-back verification, and restore), but it does not claim iOS 26 / asset 1014 support.

**Locus reuse decision:** adopt the safety principles for any future device-side maintenance feature, not its privileged writer. A normal sideloaded app cannot assume access to the protected trustd database.

## What asset 1014 changes

Community reports on 2026-11-04 onward associate the WLOC failure with a PKITrustSupplementals / PKITrustStore asset that adds an Apple-issued certificate pinning requirement for `gs-loc.apple.com` and `gs-loc-cn.apple.com`. Upstream issue #130 describes a detailed investigation on one jailbroken iOS 16.6 device; it is valuable evidence, but not an Apple statement or proof that every affected device has an identical internal state.

Upstream issue #172 identifies the asset-notification/download path as `gdmf.apple.com/v2/assets` and `updates.cdn-apple.com`. The proposed prevention workflow is for devices reset back to an earlier asset version before the newer asset is delivered. It does **not** roll an already-1014 device back to 1013. Reports in #193 and #195 are still community validation attempts, with conflicting observations and possible side effects such as App Store download and system-notification failures. Issue #200 adds another report of an iPadOS 26 device reaching 1014.

The user device is already at 1014. Blocking update endpoints now cannot remove an already-installed pinning rule. Resetting the phone or deliberately disabling Apple trust-asset security updates is not an acceptable Locus development prerequisite.

## Engineering plan

1. Preserve the current DVT engine and existing Build 11 data/configuration. Do not change the signing identity, pairing store, coordinate conversion, route, joystick, or restore path as part of this investigation.
2. Complete the physical-device DVT acceptance test when the Windows host is online: select one controlled map point, verify the DVT set result in Locus, check the system map location, then clear/restore and confirm the session closes. Record the map status-bar state separately from the Settings VPN state.
3. Keep the WLOC network engine behind a separate design gate. Before writing a provider or parser, require a documented, supported TLS validation path on the actual iOS 26.2.1 / asset 1014 device. A generic local-CA trust check is insufficient.
4. If that gate is ever met, implement independently under Locus's MIT license with: a separate Network Extension target; explicit user consent; host/path allowlists; pass-through for all unrelated traffic; fixture-based response parser tests; bounded sizes/timeouts; authenticated local control; and one-tap stop/restore.
5. Do not edit `pinningrules.sqlite3`, install root helpers, use TrollStore-only packages, or suppress Apple trust-asset updates on the user's daily iPhone as part of this project.

## Sources reviewed

- [Locus WLOC integration boundary](WLOC_ENGINE_INTEGRATION.md)
- [loc-x](https://github.com/gitfengxx/loc-x)
- [Location Spoofer v1.0.9](https://github.com/xweiba/location-spoofer)
- [WLOCRules](https://github.com/spirit-n/WLOCRules)
- [OSPinOverload](https://github.com/DKJone/OSPinOverload)
- [WLOC issue #121](https://github.com/Yu9191/wloc/issues/121), [#130](https://github.com/Yu9191/wloc/issues/130), [#172](https://github.com/Yu9191/wloc/issues/172), [#193](https://github.com/Yu9191/wloc/issues/193), [#195](https://github.com/Yu9191/wloc/issues/195), [#200](https://github.com/Yu9191/wloc/issues/200)
