#!/bin/bash
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
LAB=$1; LABEL=$2; shift 2
if [ -z "$LAB" ] || [ -z "$LABEL" ]; then
    echo "usage: tools/perflab/run.sh <lab> <label> [-PerfLabScenarios a,b] [-PerfLabRuns n] [-PerfLabX value ...]"
    exit 1
fi
APP=${PERFLAB_APP:-$(ls -d ~/Library/Developer/Xcode/DerivedData/Telegram-Mac-*/Build/Products/Debug/Telegram.app 2>/dev/null | head -1)}
OUT="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/debug/perf-lab"
RESULTS=${PERFLAB_RESULTS:-$DIR/results}
mkdir -p "$RESULTS"
if pgrep -f '^[^ ]*Debug/Telegram[.]app/Contents/MacOS/Telegram' >/dev/null; then
    echo "a Debug Telegram is already running; quit it first"
    exit 1
fi
SYS="$RESULTS/$LAB-$LABEL-system.jsonl"
rm -f "$SYS"
python3 "$DIR/syssample.py" "$SYS" 0.25 &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null' EXIT
BEFORE=$(ls "$OUT" 2>/dev/null | sort)
open -n "$APP" --args -PerfLab "$LAB" -PerfLabLabel "$LABEL" -PerfLabQuit "$@"
sleep 3
PID=$(pgrep -f '^[^ ]*Debug/Telegram[.]app/Contents/MacOS/Telegram' | head -1)
if [ -n "$PERFLAB_PROFILE" ]; then
    DELAY=${PERFLAB_PROFILE%%:*}; LIMIT=${PERFLAB_PROFILE##*:}
    TRACE="$RESULTS/$LAB-$LABEL.trace"
    rm -rf "$TRACE"
    ( sleep "$DELAY"
      xcrun xctrace record --template 'Time Profiler' --attach "$PID" --time-limit "${LIMIT}s" --output "$TRACE" >/dev/null 2>&1
      xcrun xctrace export --input "$TRACE" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > "$RESULTS/$LAB-$LABEL-profile.xml" 2>/dev/null ) &
    PROFILER=$!
fi
while kill -0 "$PID" 2>/dev/null; do sleep 1; done
[ -n "$PROFILER" ] && wait "$PROFILER"
AFTER=$(ls "$OUT" | sort)
REPORT=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | grep "^$LAB-$LABEL-.*\.json$" | tail -1)
if [ -z "$REPORT" ]; then
    echo "no report written"
    exit 1
fi
cp "$OUT/$REPORT" "$RESULTS/"
python3 "$DIR/merge.py" "$RESULTS/$REPORT" "$SYS" | tee "$RESULTS/${REPORT%.json}.txt"
if [ -s "$RESULTS/$LAB-$LABEL-profile.xml" ]; then
    echo "profile: $RESULTS/$LAB-$LABEL-profile.xml (tools/perflab/profile.py <xml> [regex])"
fi
