#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BROWSER_DEVECO="${BROWSER_DEVECO:-/Applications/DevEco-Studio.app/Contents}"
BROWSER_SDK="${BROWSER_SDK:-/Users/bingyubai/Library/OpenHarmony/Sdk}"
BROWSER_SDK_API="${BROWSER_SDK_API:-23}"
BROWSER_JAVA="$BROWSER_DEVECO/jbr/Contents/Home/bin/java"
BROWSER_LIB="$BROWSER_SDK/$BROWSER_SDK_API/toolchains/lib"
BROWSER_OUTPUT="entry/build/default/outputs/default"
printf 'sdk.dir=%s\n' "$BROWSER_SDK" > local.properties
"$BROWSER_DEVECO/tools/ohpm/bin/ohpm" install
env NODE_HOME="$BROWSER_DEVECO/tools/node" JAVA_HOME="$BROWSER_DEVECO/jbr/Contents/Home" \
  "$BROWSER_DEVECO/tools/hvigor/bin/hvigorw" --mode module -p product=default \
  -p module=entry@default -p buildMode=debug assembleHap --no-daemon
python3 - "$BROWSER_OUTPUT/profile.json" <<'PY'
import json, sys, time
from pathlib import Path
profile = json.loads(Path('signing/profile-template.json').read_text())
profile['validity'] = {'not-before': int(time.time()) - 86400,
                       'not-after': int(time.time()) + 3650 * 86400}
Path(sys.argv[1]).write_text(json.dumps(profile, indent=2))
PY
# Public SDK development keys only; no personal signing keys are stored here.
"$BROWSER_JAVA" -jar "$BROWSER_LIB/hap-sign-tool.jar" sign-profile -mode localSign \
  -keyAlias 'OpenHarmony Application Profile Release' -keyPwd 123456 \
  -profileCertFile signing/profile-chain.pem -inFile "$BROWSER_OUTPUT/profile.json" \
  -signAlg SHA256withECDSA -keystoreFile "$BROWSER_LIB/OpenHarmony.p12" \
  -keystorePwd 123456 -outFile "$BROWSER_OUTPUT/profile.p7b"
"$BROWSER_JAVA" -jar "$BROWSER_LIB/hap-sign-tool.jar" sign-app -mode localSign \
  -keyAlias 'OpenHarmony Application Release' -keyPwd 123456 \
  -keystoreFile "$BROWSER_LIB/OpenHarmony.p12" -keystorePwd 123456 \
  -appCertFile signing/app-chain.pem -profileFile "$BROWSER_OUTPUT/profile.p7b" \
  -signAlg SHA256withECDSA -inFile "$BROWSER_OUTPUT/entry-default-unsigned.hap" \
  -outFile "$BROWSER_OUTPUT/robopi-browser-signed.hap" -compatibleVersion 18
"$BROWSER_JAVA" -jar "$BROWSER_LIB/hap-sign-tool.jar" verify-app \
  -inFile "$BROWSER_OUTPUT/robopi-browser-signed.hap" \
  -outCertChain "$BROWSER_OUTPUT/verified-chain.cer" -outProfile "$BROWSER_OUTPUT/verified-profile.p7b"
