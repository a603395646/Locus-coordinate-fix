# Device install log — 2026-11-13

## Result

**Build 11 installed successfully on the iPhone 16 Pro and launched.**

- Device: iPhone 16 Pro
- iOS: 26.2.1
- Previous installed test app: 1.0.2 (Build 8)
- Installed test app: 1.0.5 (Build 11)
- Display name: Locus Fix Test
- Bundle identifier retained: `com.chrismack.locus.coordinatefix.GBWFHXQS78`
- Signing verification: `ProfileValidated = true`
- Signer identity: same saved Apple developer account used for the prior install
- Sideloadly completion: `Done / 100%`
- Sideloadly local install record updated: 2026-11-13 10:32:34 +08:00
- Sideloadly scheduler fields: `known_ttl = 7`, `refresh_at_hours = 96`
- The embedded provisioning profile's exact ExpirationDate was not independently extracted; do not treat the scheduler fields as an exact expiry timestamp.

## Recovery during installation

The install sat at 87% while the previous Locus Fix Test process remained alive in the background. After a graceful SIGTERM to that app process, Sideloadly immediately completed the install. The app was not uninstalled first.

## Launch check

The new bundle was launched through DVT and returned a running process. A device screenshot confirmed the Locus map UI loaded in Chinese.

At the time of the launch screenshot, the map banner showed **Connect LocalDevVPN** (disconnected). This is a separate runtime/tunnel state and does not indicate an installation or signing failure.

## Preservation

- The update used the same bundle identifier, so it was an in-place update rather than a second app installation.
- No app data/container deletion was performed.
- The separate original Locus app bundle was left untouched.
- No WLOC trust database, certificate, or OTA PKI settings were changed.
