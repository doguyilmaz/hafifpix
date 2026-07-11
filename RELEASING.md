# Releasing HafifPix

## Automated releases (preferred)

Push a version tag and CI does everything — build, test, sign, notarize,
staple, appcast, GitHub release:

```sh
git tag v1.0.1 && git push --tags
```

The tag is the single source of truth: `.github/workflows/release.yml` stamps
`Info.plist` from it. Required repository secrets (Settings → Secrets → Actions):

| Secret | Content | How to produce |
|--------|---------|----------------|
| `MACOS_CERT_P12` | base64 of the Developer ID .p12 | `base64 -i cert.p12 \| gh secret set MACOS_CERT_P12` |
| `MACOS_CERT_PASSWORD` | the .p12's password | `gh secret set MACOS_CERT_PASSWORD` |
| `APPLE_ID` | developer Apple ID email | `gh secret set APPLE_ID` |
| `NOTARY_PASSWORD` | app-specific password | `gh secret set NOTARY_PASSWORD` |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key | `generate_keys -x k && gh secret set SPARKLE_PRIVATE_KEY < k && rm k` |

Note: CI-built DMGs may lack the pretty Finder icon layout (Finder scripting
is limited on runners); the DMG itself is unaffected.

## Manual releases (fallback)

## One-time setup (already done on this machine)

- Sparkle EdDSA keys generated (`generate_keys`) — **private key lives in the login
  Keychain** ("Private key for signing Sparkle updates"). Back it up
  (`generate_keys -x key.priv`) and keep it safe; losing it strands existing users
  on their current version. The public key is embedded in `Resources/Info.plist`
  (`SUPublicEDKey`).
- `SUFeedURL` points to
  `https://github.com/doguyilmaz/hafifpix/releases/latest/download/appcast.xml` —
  change it if you host elsewhere (e.g. doguyilmaz.com).

## Gatekeeper signing (when you have an Apple Developer account)

Certificate created 2026-07-11: `Developer ID Application: Dogu Kaan Yilmaz (5MYT4VYJFC)`
(the .p12 backup + password live in the password manager). Build releases with:

```sh
SIGN_IDENTITY="Developer ID Application: Dogu Kaan Yilmaz (5MYT4VYJFC)" make dmg
xcrun notarytool submit dist/HafifPix-*.dmg --keychain-profile hafifpix --wait
xcrun stapler staple dist/HafifPix-*.dmg
```

(One-time: `xcrun notarytool store-credentials hafifpix --apple-id you@… --team-id 5MYT4VYJFC`
with an app-specific password from account.apple.com.)

Without this, downloaders must right-click → Open (and on macOS 15+, approve in
System Settings → Privacy & Security). Fine for friends; not fine for the public.

## Each release

1. Bump `CFBundleShortVersionString` **and** `CFBundleVersion` in `Resources/Info.plist`
   (Sparkle compares `CFBundleVersion`).
2. `make dmg` (with `SIGN_IDENTITY=…` for public releases) → `dist/HafifPix-X.Y.Z.dmg`
3. Notarize + staple (see above).
4. `make appcast` — signs the DMG with the Sparkle key and writes
   `dist/release/appcast.xml`.
5. Create a GitHub release; upload **both** the DMG and `appcast.xml` as assets.
   The feed URL always resolves to the latest release's appcast.

## Licensing note for public distribution

The app bundles GPL-licensed engines (pngquant is GPLv3-or-commercial, gifsicle
and jpegoptim are GPL). Distributing the bundle publicly means the distribution
must comply with the GPL — the original ImageOptim ships as GPL for exactly this
reason. Practically: keep the repo/source public under GPL, or acquire a
commercial pngquant license and swap the GPL engines. This also effectively
rules out the Mac App Store (GPL + App Store terms conflict, and the required
App Sandbox breaks in-place batch optimization and the bundled CLI).
