## Problem and result

Describe the concrete problem and what users experience after this change. Include a before/after example when useful.

## Validation

List relevant automated checks and their results. For documentation-only changes, say so. Separate isolated fixture/UI checks from live Roblox, account, Discord, notification and display tests; explicitly list checks that remain unverified.

## Review checklist

- [ ] Native changes stay under `native/`; the native build does not depend on `legacy/`.
- [ ] Meaningful regression checks cover changed behavior and relevant failures.
- [ ] Destructive or credential-related tests use isolated data and credential stores.
- [ ] Backups and recovery paths remain usable; behavior changes and limitations are explained.
- [ ] No credentials, cookies, authentication headers or unreviewed raw logs are included.
- [ ] Parity/acceptance checklists and user documentation are updated where applicable.
- [ ] Original GPL-3.0 license and artwork/contributor attribution are preserved.

Mark irrelevant items as not applicable in the description. Security vulnerabilities belong in the repository’s private reporting flow, not a public PR.
