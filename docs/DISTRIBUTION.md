# macOS distribution plan

Last reviewed: 2026-08-04

## Decision

Publish Neloa outside the Mac App Store as a notarized ZIP attached to each GitHub Release. A ZIP is the simplest first-release format: users download it, move `Neloa.app` to Applications, and launch it. Consider a polished DMG later if onboarding research shows that drag-to-Applications presentation materially helps.

Every public build must be:

1. Built as a universal macOS app (`arm64` and `x86_64`) on a clean macOS runner.
2. Signed with the same Apple-issued **Developer ID Application** certificate and bundle identifier, `ai.neloa.desktop`.
3. Signed with Hardened Runtime, a secure timestamp, and only the entitlements Neloa needs.
4. Submitted to Apple with `notarytool`, accepted, and stapled before packaging the final ZIP.
5. Verified with `codesign`, `stapler`, and Gatekeeper before upload.
6. Attached to an immutable, versioned GitHub Release with release notes and a SHA-256 checksum.

The self-signed `Neloa Local Development` identity created by `make setup-signing` is for local development only. It keeps macOS privacy permissions stable while rebuilding on one Mac, but Apple will not notarize it and users should never receive it.

## Apple account and signing assets

Direct distribution requires an [Apple Developer Program](https://developer.apple.com/programs/) membership, currently 99 USD per year, and a [Developer ID Application certificate](https://developer.apple.com/developer-id/). Apple requires Developer ID signing, Hardened Runtime, and a secure timestamp for notarization; a local, ad-hoc, Apple Development, or Mac Distribution certificate is not a substitute.

Create and retain:

- A Developer ID Application certificate and its private key, exported once as a password-protected `.p12` file.
- An App Store Connect API key for notarization, with its `.p8` private key, key ID, and issuer ID.
- A recovery copy of those credentials in the project owner’s password manager. Never commit them to Git.

The current entitlement file grants microphone audio input, which Hardened Runtime requires. Screen Recording, Accessibility/Input Monitoring, and Speech Recognition still require macOS consent and their usage descriptions, but do not require invented screen-capture entitlements. Review entitlements again before the first public build and add no broad runtime exceptions unless a tested feature needs one.

Moving from a local-development build to the first Developer ID build changes Neloa’s signing identity, so existing testers may need to grant privacy permissions one final time. Later official updates should retain permissions as long as the bundle identifier and Developer ID team remain stable.

## GitHub Actions

GitHub can build the binary. [Standard GitHub-hosted runners are free and unlimited for public repositories](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). A private repository uses the account’s included Actions minutes and then paid usage; macOS minutes are more expensive than Linux minutes. The Apple Developer Program is still required—GitHub does not provide an Apple signing identity or notarization credentials.

Use a release workflow on a pinned standard macOS runner, initially `macos-26`, triggered by a version tag such as `v0.3.0` and optionally by manual dispatch. The job should use a protected `release` environment and `permissions: contents: write`. Pull-request jobs must never receive release secrets.

Store these as GitHub Actions environment secrets:

- `DEVELOPER_ID_P12_BASE64`
- `DEVELOPER_ID_P12_PASSWORD`
- `DEVELOPER_ID_APPLICATION` — the full certificate name, for example `Developer ID Application: Example Name (TEAMID)`
- `APPLE_NOTARY_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`

Follow [GitHub’s temporary-keychain approach](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications): decode the certificate into the runner’s temporary directory, import it into a short-lived keychain, set the key partition list, build and sign, then let the ephemeral runner be destroyed. Generate the temporary keychain password during the job rather than storing another long-lived secret.

Prefer GitHub-maintained actions and pin every third-party action to a full commit SHA. `actions/checkout` plus the preinstalled GitHub CLI is enough to publish a release, so the release path does not need a third-party upload action.

## Planned release job

The future `.github/workflows/release.yml` should perform these steps:

1. Check out the exact version tag and ensure the working tree is clean.
2. Run `make test`. The Apple Intelligence smoke test needs a real, configured Mac, so record a passing `make agent-test` separately before approving the release.
3. Import the Developer ID certificate into a temporary keychain.
4. Build both architectures and combine them into a universal executable. Confirm both with `lipo -info`.
5. Package that prebuilt universal executable and sign it with the Developer ID identity. Before implementing the workflow, add a packaging input such as `NELOA_EXECUTABLE_PATH`; the current `make app` performs its own default-architecture build and must not be allowed to replace the universal executable.
6. Verify the signature, Hardened Runtime, secure timestamp, bundle identifier, version, and entitlements.
7. Create a temporary ZIP for notarization with Apple’s recommended `ditto -c -k --keepParent` command.
8. Run `xcrun notarytool submit ... --wait` using the App Store Connect API key and fail unless the status is `Accepted`.
9. Staple and validate the ticket on `Neloa.app`. A ZIP itself cannot be stapled, so recreate the final ZIP after stapling the app.
10. Run Gatekeeper assessment, calculate a SHA-256 checksum, and smoke-test the ZIP after extracting it into a clean temporary directory.
11. Create the GitHub Release from the tag and attach the ZIP plus checksum.

After that packaging input exists, the core release commands will resemble:

```sh
NELOA_EXECUTABLE_PATH="$RUNNER_TEMP/Neloa-universal" \
  NELOA_CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  make app
codesign --verify --deep --strict --verbose=2 dist/Neloa.app

ditto -c -k --keepParent dist/Neloa.app "$RUNNER_TEMP/Neloa-notarization.zip"
xcrun notarytool submit "$RUNNER_TEMP/Neloa-notarization.zip" \
  --key "$RUNNER_TEMP/AuthKey.p8" \
  --key-id "$APPLE_NOTARY_KEY_ID" \
  --issuer "$APPLE_NOTARY_ISSUER_ID" \
  --wait

xcrun stapler staple dist/Neloa.app
xcrun stapler validate dist/Neloa.app
spctl --assess --type execute --verbose=4 dist/Neloa.app

ditto -c -k --keepParent dist/Neloa.app "Neloa-${GITHUB_REF_NAME}-macOS-universal.zip"
shasum -a 256 "Neloa-${GITHUB_REF_NAME}-macOS-universal.zip" > "Neloa-${GITHUB_REF_NAME}-macOS-universal.zip.sha256"
gh release create "$GITHUB_REF_NAME" \
  "Neloa-${GITHUB_REF_NAME}-macOS-universal.zip" \
  "Neloa-${GITHUB_REF_NAME}-macOS-universal.zip.sha256" \
  --verify-tag --generate-notes
```

Apple’s [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) is the source of truth for `ditto`, `notarytool`, and stapling. Before enabling releases, test the downloaded artifact on a Mac that has never run a development build; this catches Gatekeeper, first-launch, permission, quarantine, icon, and Applications-folder issues that a developer Mac can hide.

## Before the first public release

- Enroll the release owner or organization in the Apple Developer Program.
- Decide whether releases are attached to the public source repository or a separate public downloads repository.
- Generate the Developer ID and App Store Connect API credentials.
- Add protected GitHub environment secrets and tag protection.
- Add universal-binary support to the packaging script.
- Implement the release workflow described above.
- Run `make agent-test` on a supported Mac with Apple Intelligence enabled and record the result for the release.
- Complete an app privacy review, especially recording disclosure, local retention/deletion, protected-app exclusions, and voice processing.
- Test install, update, permission retention, and uninstall behavior on clean Apple Silicon and Intel Macs.
- Add a support URL, privacy policy URL, release notes, checksum verification instructions, and a vulnerability-reporting path to the README.
