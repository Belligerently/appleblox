#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source toolchain.sh
xcrun swift test --disable-sandbox
