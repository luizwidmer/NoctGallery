# Local FIDO2 in Noct Gallery

**Integration status, September 22, 2026:** the user confirmed that the single-sheet registration works with their YubiKey 5.4.3 on an M2 iPad, and confirmed it also works in airplane mode. The updated implementation passes 22 security-key tests and 43 Gallery tests. The earlier two-sheet integration failed the user test and is superseded. New enrollment keeps Register and Verify in one local browser sheet, with a native state machine controlling the transition and two distinct fresh challenges. Broader key/device compatibility is not established by this one hardware check. PIV work remains paused in favor of this successful WebAuthn retry. Version 0.2.0 build 9 was uploaded and resubmitted on September 22; App Store Connect confirmed Waiting for Review. Approval remains pending.

Gallery owns registration and authentication locally. Apple's browser supplies the standard physical-key transport that ordinary iOS apps cannot access through generic USB HID. The flow does not use a remote relying-party service or an associated website.

## Ceremony

1. Gallery creates a 32-byte challenge using the system cryptographic RNG. Each challenge expires after 60 seconds.
2. A temporary Network-framework listener binds exclusively to `127.0.0.1` on an OS-assigned port. A separate random 32-byte token selects the page and its result route. The displayed origin is `http://localhost:<port>`; RP ID is `localhost`.
3. An ephemeral `ASWebAuthenticationSession` opens the bundled page. A deliberate button tap starts WebAuthn. Registration requests an external authenticator, ES256, required user verification and a non-discoverable credential preference. Assertions specify the registered IDs and USB transport hints. Apple's system sheet collects the key PIN and touch.
4. The page submits the response to its same-origin local result route. Native code verifies registration and returns a new challenge for the same sheet's Verify step. The provisional credential is not persisted. A second tap starts the assertion; the flow cannot return to registration. At most two result submissions are accepted for enrollment. Authentication uses a single assertion.
5. Native Swift code verifies the exact expected origin and challenge, RP hash, credential ID, UP/UV flags, signature and counter. Browser success alone never unlocks anything. Only a verified fresh assertion completes enrollment. A session-bound callback then closes the browser; it carries a random token, not a PIN or credential response.
6. Gallery persists only the credential ID, public key, local name and signature counter in device-only Keychain. The ordinary Key → Biometrics → PIN chain continues. Cancellation or backgrounding invalidates the attempt and closes all local connections.

The page has no external scripts, fonts, images, analytics or fetches. HTTP parsing bounds memory, rejects duplicate headers and ambiguous body framing, checks Host and Origin, and has no CORS allowance. CSP blocks other resource sources and framing. The listener allows at most eight concurrent connections, 48 accepted connections per ceremony, and five seconds per HTTP request. Each challenge has a 60-second deadline; the complete browser session allows 120 seconds for two-step registration or 60 seconds for authentication. The page embeds Gallery's logo and light/dark color palette locally, with no external asset requests.

## Scope and compatibility

The WebAuthn standard treats localhost as a trustworthy local context. Localhost is a shared browser namespace; it does not cryptographically identify Gallery as a unique application. The sandboxed credential store, unpredictable ceremony URL, exact origin and local signature verifier supply the application boundary. A malicious app cannot unlock Gallery merely by opening the callback URL or posting a claimed success. An attacker controlling Gallery's process or the OS is outside this threat model. Local denial of service remains possible; failure keeps the app locked.

New registrations do not depend on YubiKey's FIDO-over-CCID interface or firmware 5.8. They require a physically compatible FIDO2 key with ES256 and user verification. This is not a claim that every authenticator, adapter or OS version has been tested. The iPad Pro M2 with the user's YubiKey 5.4.3 completed the isolated localhost registration probe on September 22, 2026. The user subsequently confirmed that the integrated single-sheet flow works, including in airplane mode.

Gallery's NFC scanner and its permission/entitlement are removed. Apple's own sheet may offer NFC on supported devices; registration has no public USB-only control. Assertions supply USB hints. The app does not promise continuous connection monitoring for browser credentials.

Previously saved `noctgallery-app-lock.invalid` credentials stay on their original USB smart-card path, where FIDO over CCID is required. They are never silently re-scoped. Unlock and register again to add a localhost credential. Other Noctweave applications keep their existing transport policy and scopes.

## References

- [W3C Web Authentication Level 3](https://www.w3.org/TR/webauthn/) — RP IDs, localhost origins, ceremony verification and transport hints.
- [Apple ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — session-owned callbacks and ephemeral browser sessions.
- [WebKit security-key support](https://webkit.org/blog/11312/meet-face-id-and-touch-id-for-the-web/) — FIDO2, PIN and external-key support in authentication sessions.
- [Yubico FIDO applications](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-apps-fido.html) — FIDO over CCID compatibility.

## Direct transport alternatives

| Approach | M-series iPad | iPhone | Older YubiKey 5.4.3 | Constraints |
| --- | --- | --- | --- | --- |
| App-owned USBDriverKit CTAP HID driver | Possible in principle | No DriverKit support | FIDO HID is available on the key; driver is untested | DriverKit capabilities and distribution entitlements, user-enabled driver, raw USB protocol, device-level matching. No DriverKit profiles are present locally. |
| Direct FIDO over CCID | Supported on compatible keys | Supported on compatible keys | No FIDO-over-CCID applet | YubiKey introduces FIDO over CCID in firmware 5.8. Cannot add that applet with app code. |
| App-owned PIV challenge/signature | Via smart-card API | Via smart-card API on supported wired hardware/OS | PIV P-256 supported | Separate PIV credential/PIN and enrollment. Not compatible with FIDO-only keys. No existing slot may be overwritten implicitly. |
| Local browser WebAuthn | Standard system transport | Standard system transport | Isolated registration succeeded | Still uses Apple's FIDO transport UI; the user confirmed the replacement single-sheet flow works, including in airplane mode. |

Apple's [DriverKit platform documentation](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados) limits iPad drivers to M-series devices. [Apple DTS confirms custom HID access](https://developer.apple.com/forums/thread/789712) can use raw USB with device-level matching, with hot-plug and hardware caveats. Distribution requires [DriverKit entitlements](https://developer.apple.com/documentation/DriverKit/requesting-entitlements-for-driverkit-development). The iPhone SDK does not expose generic USB HID access. [Yubico's PIV specification](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-apps-piv.html) lists P-256 support for firmware 5.0–5.6.

Any PIV implementation must inventory slots read-only, bind a specific app credential and public key, and require fresh local challenge signatures with the configured PIN/touch policy. It must not reset the authenticator, guess a PIN or management key, or repurpose a populated slot. Neither a PIV option nor an iPad-only driver is an honest substitute for universal FIDO2 support.
