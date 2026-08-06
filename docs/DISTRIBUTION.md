# macOS distribution plan

Last reviewed: 2026-08-04

## Current decision: unsigned GitHub previews

Neloa will initially ship as an unsigned universal ZIP attached to each GitHub Release. This avoids Apple Developer Program fees while the product is in preview. It is a deliberate tradeoff: GitHub can build the app, but it cannot give Neloa an Apple-issued Developer ID or notarize it.

Each release contains:

- `Neloa-<version>-macOS-universal-unsigned.zip`, containing an ad-hoc-signed app for Apple Silicon and Intel Macs.
- A matching `.sha256` checksum.
- Release notes that prominently identify the build as an unsigned preview.

The ad-hoc signature gives the bundle an internal code signature and stable bundle identifier. It does **not** establish the developer's identity, satisfy Gatekeeper, or imply that Apple scanned the app. Never distribute the private key for the `Neloa Local Development` identity; that identity exists only to keep permissions stable on its owner's development Mac.

## What users experience

After downloading and moving Neloa to Applications, the first launch is blocked because the developer cannot be verified. The supported installation flow is:

1. Try to open Neloa and dismiss the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security** and choose **Open Anyway**.
4. Authenticate and confirm **Open**.
5. Grant Screen Recording, Accessibility, Microphone, and Speech Recognition when Neloa requests them; reopen Neloa if macOS asks.

These steps follow Apple's [documented process for opening an unnotarized app](https://support.apple.com/102445). Do not tell users to disable Gatekeeper globally or strip quarantine metadata. The override should apply only to the Neloa build they intentionally downloaded.

Unsigned releases are appropriate for technical testers and early adopters, not a polished mainstream launch. An update may trigger Gatekeeper or permission prompts again because the app lacks a stable Apple-issued signing identity. Managed Macs may prohibit unsigned software entirely.

## Reproducible local packaging

Run:

```sh
make test
make unsigned-release RELEASE_VERSION=0.2.17 BUILD_NUMBER=20
```

The release script:

1. Builds Neloa for `arm64` and `x86_64` with a macOS 15 deployment target.
2. Combines both executables into a universal binary.
3. Builds the app bundle with the checked-in icon, property list, and entitlements.
4. Forces ad-hoc signing, even if the developer has a local signing identity.
5. Verifies the signature and both architectures.
6. Creates a ZIP with `ditto`, computes its SHA-256 checksum, extracts it into a temporary directory, verifies the extracted app again, and runs its self-tests.

The downloadable ZIP and checksum are placed in `dist/`. The ad-hoc app bundle is assembled under `.build/unsigned-release/staging/`; it never replaces `dist/Neloa.app`, which is the stable locally signed development build. The packaging script fingerprints an existing local bundle before release assembly and fails if that fingerprint changes. This separation matters because macOS privacy grants are tied to an app's signing identity. Replacing the development app with the ad-hoc release bundle makes an enabled Screen Recording switch appear ineffective to the running app.

Version tags must match `CFBundleShortVersionString` in `Resources/Info.plist`.

## GitHub release automation

`.github/workflows/release.yml` runs when a `v*` tag is pushed. It verifies the version, runs deterministic checks, packages the universal ZIP, and creates a GitHub Release. Public repositories can use [standard GitHub-hosted runners for free](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

A typical release is:

```sh
git tag v0.2.17
git push origin v0.2.17
```

Before tagging:

- Ensure `CFBundleShortVersionString` and `CFBundleVersion` are updated.
- Run `make test` and `make agent-test` on a configured Mac.
- Review privacy-sensitive changes and the requested entitlements.
- Test the ZIP on a Mac or macOS account that has not run a development build.
- Confirm the icon, first-launch warning, permission flow, recording, timeline review, and replay.

The workflow requires only the repository-provided GitHub token. There are no Apple certificates, notarization keys, or release secrets.

## Future trusted distribution

If Neloa later targets nontechnical users, switch the same ZIP pipeline to a Developer ID Application signature and Apple notarization. Apple currently requires membership in the [Apple Developer Program](https://developer.apple.com/support/developer-id/) for that identity. Existing builds signed while a Developer ID certificate was valid can continue to run after certificate expiry, but signing new releases requires a valid certificate.

Possible ways to fund that transition include project sponsorship, publishing through a trusted organization that takes responsibility for the release, or Apple's fee waiver for an eligible nonprofit, accredited educational institution, or government entity. Until then, every download and release note must continue to say **unsigned preview** clearly.
