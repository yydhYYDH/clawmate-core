#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STARTER_DEVECO="${STARTER_DEVECO:-/Applications/DevEco-Studio.app/Contents}"
if [ ! -x "$STARTER_DEVECO/tools/hvigor/bin/hvigorw" ]; then
  echo '请设置 STARTER_DEVECO 为 DevEco Studio Contents 路径。' >&2
  exit 1
fi
"$STARTER_DEVECO/tools/ohpm/bin/ohpm" install
env NODE_HOME="$STARTER_DEVECO/tools/node" JAVA_HOME="$STARTER_DEVECO/jbr/Contents/Home" DEVECO_SDK_HOME="$STARTER_DEVECO/sdk" \
  "$STARTER_DEVECO/tools/hvigor/bin/hvigorw" --mode module -p product=default \
  -p module=entry@default -p buildMode=debug assembleHap --no-daemon
