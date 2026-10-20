#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STARTER_DEVECO="${STARTER_DEVECO:-/Applications/DevEco-Studio.app/Contents}"
"$STARTER_DEVECO/tools/node/bin/node" --test tests/*.test.cjs
python3 -m unittest discover -s tests -p 'test_*.py' -v
