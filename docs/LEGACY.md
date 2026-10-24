# Inherited AppleBlox implementation

AppleBlox Native is a SwiftUI fork of [AppleBlox](https://github.com/AppleBlox/appleblox). The inherited Svelte/Neutralino application remains in this repository as migration reference. It is separate from the native app in `native/`.

## Source layout

- `frontend/`: Svelte interface, settings, Roblox integration, and web assets.
- `scripts/`: Neutralino packaging, installers, and native sidecar utilities.
- `package.json` and `neutralino.config.json`: legacy application metadata; these do not version the native app.
- `CHANGELOG_0.9.0.md`: historical upstream release notes; these are not AppleBlox Native release notes.
- `.github/assets/src*.png`: screenshots of the original interface.

## Legacy development

The following commands build the inherited application, not AppleBlox Native:

```sh
bun install
bun run --bun dev
bun run --bun build
bun run --bun release
```

The original implementation uses Svelte and NeutralinoJS, with Objective-C/Swift sidecars. See [the sidecar documentation](../scripts/build/sidecar/README.md) for those utilities. Native SwiftUI development instead uses the scripts in `native/` and full Xcode.

## Upstream resources and credits

- [Original AppleBlox source and contributors](https://github.com/AppleBlox/appleblox).
- [Original AppleBlox releases](https://github.com/AppleBlox/appleblox/releases), which are separate from this fork’s downloads.
- [Original AppleBlox website](https://appleblox.com) and [documentation](https://docs.appleblox.com), which describe the upstream project.
- Original logo: @typeofnull.
- Original inspiration: @pizzaboxer’s [Bloxstrap](https://github.com/pizzaboxer/bloxstrap).
- Legacy interface icons: lucide-svelte and icons8.
- Legacy `alerter` binary: [vjeantet/alerter](https://github.com/vjeantet/alerter).
- Legacy Discord sidecar: [AppleBlox/Discord-RPC-cli](https://github.com/AppleBlox/Discord-RPC-cli).
- The original README credits assistance from ClaudeAI and ChatGPT for the Objective-C sidecar.

The inherited code and this fork retain the repository’s [GPL-3.0 license](../LICENSE). Historical upstream feature descriptions and privacy statements should not be read as documentation for the native edition; consult the native guide for its current behavior.
