#!/bin/bash
set -euo pipefail

xcodebuild build \
  -scheme ora \
  -destination "platform=macOS,arch=arm64" \
  -configuration Debug \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO | xcbeautify
