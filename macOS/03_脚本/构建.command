#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$repo_dir/scripts/build.sh" "${1:-release}"
