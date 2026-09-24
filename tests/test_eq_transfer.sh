#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/openscq30" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OMACORE_TEST_LOG"
case "$*" in
  *list-settings*) printf '%s\n' '[{"categoryId":"equalizerImportExport","settings":[{"settingId":"exportCustomEqualizerProfiles","setting":{"options":["Bass","Jazz, Live"]}}]},{"categoryId":"equalizer","settings":[{"settingId":"volumeAdjustments","type":"equalizer","setting":{"bandHz":[100,200],"fractionDigits":1,"min":-120,"max":134}}]}]' ;;
  *exportCustomEqualizerProfilesOutput*) printf '%s\n' '[{"settingId":"exportCustomEqualizerProfilesOutput","value":{"type":"string","value":"[{\"name\":\"Bass\",\"volumeAdjustments\":[1.5,0]}]"}}]' ;;
esac
EOF
cat >"$tmp/wl-copy" <<'EOF'
#!/usr/bin/env bash
cat >"$OMACORE_TEST_COPIED"
EOF
cat >"$tmp/wl-paste" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$OMACORE_TEST_CLIP"
EOF
chmod +x "$tmp/openscq30" "$tmp/wl-copy" "$tmp/wl-paste"
export PATH="$tmp:$PATH" OMACORE_TEST_LOG="$tmp/log" OMACORE_TEST_COPIED="$tmp/copied"
./omacore-eq-transfer export 00:00:00:00:00:00 | rg -q 'Copied 1'
jq -e '.[0].name=="Bass"' "$tmp/copied" >/dev/null
rg -Fq 'exportCustomEqualizerProfiles="Bass","Jazz, Live" --get exportCustomEqualizerProfilesOutput --json' "$tmp/log"
export OMACORE_TEST_CLIP='[{"name":"New","volumeAdjustments":[1.5,0]}]'
./omacore-eq-transfer import 00:00:00:00:00:00 | rg -q 'Imported 1'
rg -Fq 'importCustomEqualizerProfiles=[{"name":"New","volumeAdjustments":[1.5,0]}]' "$tmp/log"
before=$(wc -l <"$tmp/log")
export OMACORE_TEST_CLIP='[{"name":"Bad","volumeAdjustments":[100,0]}]'
if ./omacore-eq-transfer import 00:00:00:00:00:00 >/dev/null 2>&1; then
  echo 'Out-of-range EQ import unexpectedly succeeded' >&2
  exit 1
fi
after=$(wc -l <"$tmp/log")
[ "$after" -eq $((before + 1)) ] || { echo 'Invalid EQ reached the write command' >&2; exit 1; }
echo 'EQ transfer checks passed.'
