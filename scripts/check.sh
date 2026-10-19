#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
with_assets=false
case "${1:-}" in
  '') ;;
  --with-assets) with_assets=true ;;
  *) echo 'Usage: scripts/check.sh [--with-assets]' >&2; exit 2 ;;
esac
if "$with_assets"; then
  export NAIJIA_ASSET_ROOT="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "${NAIJIA_ASSET_ROOT:-$repo_dir/Resources}")"
  [[ -f "$NAIJIA_ASSET_ROOT/运行资源清单.json" ]] || { echo 'Missing authorized runtime assets' >&2; exit 2; }
fi
cd "$repo_dir/macOS"
swift --version
for configuration in debug release; do
  swift build -c "$configuration" --product Naijia
  swift run -c "$configuration" NaijiaResilienceChecks
  swift run -c "$configuration" NaijiaUsageChecks
  swift run -c "$configuration" NaijiaUsageHistoryChecks
  if "$with_assets"; then swift run -c "$configuration" NaijiaChecks; fi
done
python3 Tests/LocalizationChecks/check.py
python3 -m unittest discover -s Tests/PackagingChecks -v
python3 "$repo_dir/scripts/verify_release.py"
