#!/usr/bin/env bash
# 抓取 ClawMate Core 的文本日志（不依赖截图）：
#   1) hilog：App 接入 Logger 后的所有 Agent/HDC/报错日志
#   2) uitest dumpLayout：把界面上显示的文本（含失败信息）导出成 JSON 并提取
#
# 用法：
#   ./scripts/capture_logs.sh            # 自动找 USB 设备
#   UDID=<udid> OUT=/tmp/cc ./scripts/capture_logs.sh
set -u

HDC="${HDC:-hdc}"
UDID="${UDID:-$("$HDC" list targets | sed '/^[[:space:]]*$/d' | grep -v '^COM' | head -1)}"
OUT="${OUT:-/tmp/opencode/clawmate_logs}"
TAG="${TAG:-ClawMateCore}"
mkdir -p "$OUT"

if [ -z "$UDID" ]; then
  echo "未找到 USB 设备；先连接并确认 'hdc list targets'" >&2
  exit 1
fi
echo "device=$UDID  out=$OUT"

echo "[1/2] hilog ..."
timeout 20 "$HDC" -t "$UDID" hilog -x -T "$TAG" > "$OUT/hilog.txt" 2>&1 || true
echo "  -> $OUT/hilog.txt ($(wc -l < "$OUT/hilog.txt") lines)"

echo "[2/2] uitest dumpLayout ..."
"$HDC" -t "$UDID" shell "uitest dumpLayout -p /data/local/tmp/cc_layout.json" >/dev/null 2>&1
"$HDC" -t "$UDID" file recv /data/local/tmp/cc_layout.json "$OUT/layout.json" >/dev/null 2>&1
"$HDC" -t "$UDID" shell "rm -f /data/local/tmp/cc_layout.json" >/dev/null 2>&1

python3 - "$OUT/layout.json" "$OUT/ui_text.txt" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("layout parse failed:", e); raise SystemExit(0)

def texts(n):
    a = n.get('attributes', {})
    t = a.get('text')
    out = [t] if t else []
    for c in n.get('children') or []:
        out += texts(c)
    return out

lines = []
for child in d.get('children', []):
    if child.get('attributes', {}).get('bundleName') == 'com.clawmate.core':
        lines = texts(child)
open(sys.argv[2], 'w').write('\n'.join(lines))
print("  -> %s (%d texts)" % (sys.argv[2], len(lines)))
for t in lines:
    if 'FAILED' in t or '失败' in t or 'error' in t.lower() or 'DEVICE_OUTPUT' in t:
        print("     !", t.replace('\n', ' ')[:300])
PY
