# Security policy

## Supported code

This repository develops the AppleBlox Native preview in `native/`. Native changes are currently reviewed in PR #1 on `swiftui-foundation` until merged into `main`. The inherited app in `legacy/` is reference material and is not included in native builds. There is no general security-support guarantee for archived upstream code or old previews.

## Report privately

Open this repository’s **Security** tab and choose **Report a vulnerability**. Private vulnerability reporting is enabled for this fork. Do not post security reports, exploit details, account cookies or session tokens in public issues, discussions or pull requests.

Include the affected native version/build and macOS version, a concise impact description, and the smallest reproducible example using test data. Explain whether account storage, launch URLs, imported files, backups, updates or support exports are involved. Redact private identifiers and local paths from attachments. Never include `.ROBLOSECURITY` cookies, Keychain exports, authentication headers or someone else’s account data.

If you exposed a credential, revoke or replace it through the affected service. Do not paste it again to demonstrate the issue. A reviewed support bundle can help with ordinary troubleshooting, but inspect every included file before sharing it.

Reports are handled on a best-effort basis. Do not assume a response or fix deadline. Coordinate disclosure privately until maintainers have assessed the report. AppleBlox Native is an independent project; Roblox platform vulnerabilities should be reported through Roblox’s own security process.
