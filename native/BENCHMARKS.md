# Initial live performance observation

2026-10-28. This is a preliminary launcher-overhead observation, not a completed performance benchmark or proof of an improvement.

## Setup

- Apple M2, 8 GB RAM, AC power; built-in display, unchanged window and stationary camera.
- Roblox 0.745.0.7451137 using Metal, 2940 × 1580 client framebuffer.
- Catalog Avatar Creator (place 7041939546), user-provided private server. Private invite and account details are excluded.
- User confirmed Manual graphics at maximum and a 240 FPS selection; observed output remained approximately 60 FPS. The on-disk settings XML still contained earlier values during the running session, so the current selections were user-confirmed rather than verified from that file. Display refresh was not independently measured.
- Native preview 0.17.1 (36), built from the current development branch. A temporary app copy used an isolated data directory with default settings, updates and integrations disabled. Normal preferences and Player resources were preserved.

## Observations

Three sequential 30-second process captures, each with 31 samples, used the same running Player. AppleBlox was closed for the first and third captures, and open behind Roblox for the second. This tests idle launcher overhead; it does not test launching through AppleBlox or an applied engine profile.

| Measurement | Launcher closed | Isolated launcher open | Launcher closed again |
| --- | ---: | ---: | ---: |
| Player CPU, elapsed process CPU time / wall time | 80.1% | 69.2% | 86.2% |
| Peak Player resident memory | 419.3 MiB | 380.4 MiB | 447.0 MiB |
| Sparse overlay FPS observations | 58.6–60.0 | 59.8–60.1 | 59.9–60.1 |
| Sparse overlay Render-work observations | 2.5–2.6 ms | 2.2 ms | 2.8–3.0 ms |

CPU uses cumulative process-time differences over each capture; 100% represents one CPU core. Resident memory is not total system or GPU memory. Overlay observations were collected around the captures, with three, two and two screenshots respectively; they are not continuous frame traces or synchronized window averages. The overlay's Render-work value is not independently measured GPU frame time or end-to-end frame latency.

Five separate idle launcher process samples reported 0.0% CPU at `ps` reporting precision and 19.5–24.3 MiB resident memory. These brief samples do not establish zero CPU usage or overhead with Discord, history, updates or other integrations enabled.

## Interpretation and remaining work

The launcher showed small idle resource usage in this configuration. All conditions stayed near the observed 60 FPS ceiling. Lower Player CPU/memory in the middle capture cannot be attributed to AppleBlox: scene activity, allocation changes, elapsed time and observation tools were uncontrolled, and this was a single ordered comparison. No FPS improvement is established.

Still required: repeated and order-balanced runs, native launch acceptance, a reviewed tuned profile followed by a Player restart, equivalent visual-quality documentation, and continuous frame measurements if reporting averages, frame consistency or 1% lows. Changing graphics quality must be disclosed as a quality/performance tradeoff. The private-server rejoin requires user interaction; it was not automated. The full benchmark checklist item remains open.

Raw screenshots, process samples and original-settings recovery copies remain local and private. The temporary launcher was closed afterward; Roblox was left in the game. No engine flags, mods, virtual display or account selection were applied.


## FPS-unlock live test

The same M2 and private experience were tested at user-confirmed Manual graphics 10 with the saved 240 FPS selection, the same window dimensions and no engine flags or resource mods. This was a fresh Player launch and manual rejoin, so it is a functional unlock check rather than a controlled repeated benchmark.

Initial attempts exposed two native defects: Retina virtual-mode sizing/HiDPI configuration differed from the original helper, and mirroring was requested before macOS registered the new display. The bridge now uses logical Retina dimensions with HiDPI enabled and a 60 Hz fallback mode. Main-actor startup asynchronously polls display readiness for at most five seconds before mirroring and launching Player. Cancellation and stopping during registration prevent successful startup; partial display resources remain owned for rollback. Fixed-stage diagnostics avoid exposing raw exception details.

After those corrections, CoreGraphics reported two online displays, active mirroring and a 240 Hz main mode at 1470 × 956 logical / 2940 × 1912 pixel resolution. Four saved in-game overlay FPS snapshots were **91.5, 93.0, 105.0 and 93.6 FPS**; Render-work readings were **2.0, 2.1, 1.9 and 2.2 ms**. These sparse values are not a continuous average or 1% low. The 30-second Player process capture recorded **86.4% CPU** from elapsed process CPU time and **468.6 MiB peak resident memory**. GPU utilization, power and thermal impact were not measured.

Explicit Stop removed the virtual display and mirroring and restored one online display at the original 60 Hz, 1470 × 956 logical / 2940 × 1912 pixel mode. A subsequent game screenshot showed **60.3 FPS**. The isolated FPS preference was turned off and the test launcher closed. The physical panel remains 60 Hz; rendering above 60 FPS does not make it display 240 distinct frames per second. Input-latency benefits were not measured.

This verifies initial startup, above-60 rendering in this experience, failed-start rollback and explicit Stop on this Mac. It does not close last-Player exit, active app-quit, crash/hotplug or cross-hardware acceptance. All **179 native tests** pass, including display-readiness, cancellation and stop-during-registration checks; automated tests use fake display drivers and do not change display modes.


## Manual quality 5 comparison

The user changed Roblox to Manual quality 5 with the 240 FPS selection retained. After quitting Player, the saved XML confirmed `SavedQualityLevel` 5 and `FramerateCap` 240. Both measured process captures kept the isolated launcher idle behind Roblox. A preliminary baseline process capture that included opening the launcher was superseded by a fresh 30-second capture with it already open.

| Measurement | Normal 60 Hz mode | Temporary 240 Hz mode |
| --- | ---: | ---: |
| Four overlay FPS snapshots | 60.0, 60.1, 60.1, 60.0 | 126.9, 125.5, 168.5, 153.9 |
| Render-work snapshots | 2.9, 3.1, 2.7, 2.8 ms | 1.7, 2.3, 1.7, 1.6 ms |
| Player process CPU over 30 seconds | 75.6% | 99.2% |
| Peak Player resident memory | 510.2 MiB | 522.4 MiB |

The unlocked run used a fresh Player and manual private-server rejoin. Camera/platform angle and avatar idle poses were not reproduced exactly across rejoins, and no thermal, power, GPU or background-work controls were applied. These observations show above-60 rendering at both quality levels, with higher sampled rates at level 5, but do not establish a precise quality-setting speedup. Lower quality is a visual tradeoff. All FPS figures remain sparse snapshots, not continuous averages or frame-consistency statistics.

Normal AppleBlox quit while the workaround was active successfully removed the temporary display and mirroring and restored the original one-display 60 Hz mode and resolution. The launcher process exited, Roblox remained in the game, and the isolated FPS preference was reset off afterward. The user's Manual quality 5 selection was retained. Last-Player exit, crash recovery and hotplug remain untested.
