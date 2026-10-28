# Native release automation

## Setup

Push the native release workflow to the branch being developed. GitHub must have Actions enabled for this fork. No personal access token or extra release secret is needed: the release job requests `contents: write` for its temporary `GITHUB_TOKEN`. Pull-request validation has read-only access and never publishes.

Merge the native app and workflow into `main` when ready for the first stable release. Until then, pushes to the development branch produce prereleases. `main` currently contains the inherited application, so it cannot produce a native release until the native code is merged.

Use **Actions → Native build and release → Run workflow** on a selected branch to retry or release its current commit manually. GitHub exposes this button once the workflow exists on the default branch. Failed runs can also be rerun directly.

## Version policy

`.github/scripts/release_config.json` sets a version floor of `0.1.0` and the stable branch `main`. Stable native tags determine the next patch version. Prereleases target the next stable version and use a separate development counter. Set the floor to `0.2.0` when deliberately beginning that minor release; do not edit the inherited `legacy/package.json` to version the native app.

Version reservations use atomic Git ref creation, so overlapping pushes cannot reserve the same version for different commits. No concurrency group cancels pending pushes. Versions are allocated after tests and compilation pass. A packaging/upload failure can leave a reserved tag or draft; rerunning the job reuses it. Manually deleting native tags or releases can disrupt this history; keep them.

Build identifiers use the GitHub run ID and the commit's position in the push. These are separate from public versions. The source plist retains its local preview version; release packaging overrides it. About displays the complete release version, including `-dev.N`, while the bundle's short version remains numeric.

A native commit may have one prerelease and one stable release when it reaches `main`. The same commit/channel is reused on retries and when pushed to another development branch. Development counters are shared across branches. Overlapping pushes may finish in a different order from their creation; version numbers follow successful version reservation, not commit timestamps.

## Commit selection

Pushes to all branches are inspected without GitHub's file-list path-filter limit. The planner reads the full local Git history and selects first-parent commits changing `native/` (excluding Markdown), the native workflow/helpers, or `LICENSE`. Docs-only pushes only run the small planning job.

`history_start` is the last preview commit before this automation. It prevents a newly created branch from rebuilding years of inherited upstream history. For new branches, qualifying commits after that baseline are selected; previously published commit/channel pairs are skipped. Do not move this baseline during routine development. Force-pushes select newly reachable commits relative to the previous tip. Deleted branches and tag pushes do not publish.

Each selected source commit is built in its own detached worktree. The workflow's current build helper supplies universal packaging; tests, Swift sources, metadata, and branding are taken from the source commit. Failures are collected so a broken older commit does not prevent newer commits being attempted. Very large pushes can reach GitHub's six-hour job limit; rerun to resume unfinished releases.

## Packages and signing

CI uses GitHub’s `xcode-27` runner with full Xcode (the default Xcode 26.6 compiler on `macos-26` crashes compiling the engine UI), tests the host architecture, cross-compiles both `arm64` and `x86_64`, and verifies the universal executable with `lipo`. It stamps the version, ad-hoc signs and verifies the bundle, then creates ZIP, DMG, and checksum assets. Intel runtime behavior still needs testing on an Intel Mac.

Assets upload to a draft before publication, so download links are available when the release becomes public. Stable releases use GitHub's version-based latest selection; prereleases never become the stable latest download. Existing published releases are left intact on retries. Packaging artifacts are also retained on the workflow run for 14 days.

Developer ID signing and Apple notarization are not configured. The old VirusTotal workflow is manual-only and requires `VT_API_KEY`; automatic native releases do not claim a VirusTotal scan. Releases created with `GITHUB_TOKEN` do not trigger a second release-event workflow.

## Local verification

```sh
python3 -m unittest discover -s .github/scripts -p 'test_*.py' -v
bash native/test.sh
APPLEBLOX_UNIVERSAL=1 bash native/build.sh
```

The automation tests use temporary Git repositories and a fake GitHub API; they never create real tags or releases.


## Workflow action revisions

Active workflow actions are pinned to the exact commits resolved from their existing version tags on 2026-10-28: checkout v7 (`3d3c42e5aac5ba805825da76410c181273ba90b1`), upload-artifact v7 (`cf430e030ddbb5b0abf93d22962f4752f3646cd9`), and the manual VirusTotal action v4 (`d34968c958ae283fe976efed637081b9f9dcf74f`). Version comments retain the update context. Update pins through a reviewed PR after checking the owning repository and release changes.

The repository allowlist permits the exact VirusTotal SHA and temporarily retains its existing `@v4` entry for the unchanged default branch. After this PR merges, remove that temporary entry and enable the repository's SHA-only action policy. Do not enable it while old main workflows still use floating tags. Default token permissions and external-contributor approval requirements remain unchanged.
