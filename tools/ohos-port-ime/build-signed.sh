#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
IME_DEVECO="${IME_DEVECO:-/Applications/DevEco-Studio.app/Contents}"
IME_SDK="${IME_SDK:-/Users/bingyubai/Library/OpenHarmony/Sdk}"
IME_SDK_API="${IME_SDK_API:-23}"
IME_JAVA="$IME_DEVECO/jbr/Contents/Home/bin/java"
IME_LIB="$IME_SDK/$IME_SDK_API/toolchains/lib"
IME_OUTPUT="entry/build/default/outputs/default"
printf 'sdk.dir=%s\n' "$IME_SDK" > local.properties
"$IME_DEVECO/tools/ohpm/bin/ohpm" install
env NODE_HOME="$IME_DEVECO/tools/node" JAVA_HOME="$IME_DEVECO/jbr/Contents/Home" \
  "$IME_DEVECO/tools/hvigor/bin/hvigorw" --mode module -p product=default \
  -p module=entry@default -p buildMode=debug assembleHap --no-daemon
python3 - "$IME_OUTPUT/profile.json" <<'PY'
import json, sys, time
from pathlib import Path
profile = json.loads(Path('signing/profile-template.json').read_text())
profile['validity'] = {'not-before': int(time.time()) - 86400,
                       'not-after': int(time.time()) + 3650 * 86400}
Path(sys.argv[1]).write_text(json.dumps(profile, indent=2))
PY
# Public SDK development keys only; no personal signing keys are stored here.
"$IME_JAVA" -jar "$IME_LIB/hap-sign-tool.jar" sign-profile -mode localSign \
  -keyAlias 'OpenHarmony Application Profile Release' -keyPwd 123456 \
  -profileCertFile signing/profile-chain.pem -inFile "$IME_OUTPUT/profile.json" \
  -signAlg SHA256withECDSA -keystoreFile "$IME_LIB/OpenHarmony.p12" \
  -keystorePwd 123456 -outFile "$IME_OUTPUT/profile.p7b"
"$IME_JAVA" -jar "$IME_LIB/hap-sign-tool.jar" sign-app -mode localSign \
  -keyAlias 'OpenHarmony Application Release' -keyPwd 123456 \
  -keystoreFile "$IME_LIB/OpenHarmony.p12" -keystorePwd 123456 \
  -appCertFile signing/app-chain.pem -profileFile "$IME_OUTPUT/profile.p7b" \
  -signAlg SHA256withECDSA -inFile "$IME_OUTPUT/entry-default-unsigned.hap" \
  -outFile "$IME_OUTPUT/clawmate-pinyin-signed.hap" -compatibleVersion 18
"$IME_JAVA" -jar "$IME_LIB/hap-sign-tool.jar" verify-app \
  -inFile "$IME_OUTPUT/clawmate-pinyin-signed.hap" \
  -outCertChain "$IME_OUTPUT/verified-chain.cer" -outProfile "$IME_OUTPUT/verified-profile.p7b"
