#!/bin/zsh
set -euo pipefail

# Xcode Cloud usually fails TestFlight distribution if the build number (CFBundleVersion)
# is reused. This project uses CURRENT_PROJECT_VERSION, so we bump it per CI run.
#
# Docs: Xcode Cloud exposes CI_BUILD_NUMBER. If it's missing, we do nothing.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Xcode Cloud runs scripts with CWD set to the script folder, so don't rely on $(pwd).
# Prefer Xcode Cloud's repo path env vars when present, otherwise resolve relative to this script.
ROOT_DIR="${CI_PRIMARY_REPOSITORY_PATH:-${CI_WORKSPACE:-$(cd "$SCRIPT_DIR/.." && pwd)}}"
PROJECT_PBXPROJ="$ROOT_DIR/endar.xcodeproj/project.pbxproj"

if [[ -z "${CI_BUILD_NUMBER:-}" ]]; then
  echo "CI_BUILD_NUMBER is not set; skipping build number bump."
  exit 0
fi

if [[ ! -f "$PROJECT_PBXPROJ" ]]; then
  echo "Missing project file: $PROJECT_PBXPROJ"
  exit 1
fi

echo "Setting CURRENT_PROJECT_VERSION to CI_BUILD_NUMBER=$CI_BUILD_NUMBER"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\\1${CI_BUILD_NUMBER};/g" "$PROJECT_PBXPROJ"
