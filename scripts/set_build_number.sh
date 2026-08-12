#!/bin/sh
# Sets CFBundleVersion in the built app Info.plist to the git commit count.
# Invoked as an Xcode Run Script build phase (always runs).
set -euo pipefail

ROOT="${SRCROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || true)"

if [ -z "${BUILD_NUMBER}" ]; then
  BUILD_NUMBER="${CURRENT_PROJECT_VERSION:-1}"
  echo "warning: git commit count unavailable; using CURRENT_PROJECT_VERSION=${BUILD_NUMBER}"
fi

INFO_PLIST="${TARGET_BUILD_DIR:?}/${INFOPLIST_PATH:?}"

if [ ! -f "$INFO_PLIST" ]; then
  echo "error: Info.plist not found at ${INFO_PLIST}"
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$INFO_PLIST"
echo "CFBundleVersion set to ${BUILD_NUMBER}"
