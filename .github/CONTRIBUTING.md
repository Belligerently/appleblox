# Contributing to AppleBlox Native

AppleBlox Native is an independent SwiftUI fork of AppleBlox. Native development lives in `native/`; `legacy/` is retained as upstream reference and is not part of the native build. Preserve the GPL-3.0 license and original artwork/contributor credits.

## Workflow

Open pull requests against `main`. Until the native migration PR is merged, coordinate changes with PR #1 and its `swiftui-foundation` branch. Keep changes focused and explain the user-visible result. Main requires passing GitHub Actions validation, an up-to-date branch, and resolved review conversations. Direct pushes, force pushes and deletion are blocked. Required human approvals are currently zero for solo maintenance; review remains encouraged.

## Build and verify

Use full Xcode 27 or later, Swift 6 language mode, and a Mac capable of building the macOS 14+ app. From the repository root:

```sh
bash native/test.sh
APPLEBLOX_UNIVERSAL=1 bash native/build.sh
python3 -m unittest discover -s .github/scripts -p "test_*.py" -v
```

Keep UI state on MainActor and file/network services behind appropriate concurrency boundaries. Add meaningful regression tests for changed behavior. Use isolated data folders and fixtures for resets, credentials, backups and mods. Never test destructive operations against a contributor’s real data. Describe any live Roblox, Discord, notification or display checks separately from automated checks.

## Safety and reporting

Do not post cookies, Keychain contents, session tokens or unreviewed raw Roblox logs. Prefer the reviewed local support bundle and inspect it before attaching. Report suspected security vulnerabilities privately through the repository Security tab; do not open a public issue containing credentials or exploit details.

Update `native/PARITY.md` and `native/SOURCE-PARITY.md` when parity changes. Distinguish implemented behavior from pending live acceptance, and support performance claims with repeatable benchmarks. Native releases follow `.github/RELEASING.md`; documentation-only changes do not create app releases.
