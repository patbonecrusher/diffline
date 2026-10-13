#!/bin/bash
# Regenerates the website's icons and social card from Design/icon.svg into docs/.
#   Design/build-site-assets.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift Design/render-site-assets.swift Design/icon.svg docs
cp Design/icon.svg docs/icon.svg
echo "done"
