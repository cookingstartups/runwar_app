#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter analyze
flutter test
