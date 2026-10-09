#!/bin/sh
# Tests scripts/lisp-start-watchdog against a fake command: no CCL, no
# Lisp, just a small script with counter and pid files and short (2s)
# windows. `make check-watchdog` runs this; it is pure shell and fast.
# Checks name themselves, and the exit status is non-zero if any failed.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
watchdog=$root/scripts/lisp-start-watchdog
tmp=$(mktemp -d)
# Clean up on any exit; a signal exits with its conventional status, which
# runs the EXIT trap once.
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
pass=0
fail=0

ok()    { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad()   { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }
check() { name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

# Whether the fakes started for a case still run, by the pids they wrote
# to $pids. `kill -0` needs no procps: neither CI's image nor the Guix
# container has pgrep, and `! pgrep` passes there whatever runs. A fake the
# watchdog killed is gone, not a zombie: the watchdog's wrapper, its
# parent, reaps it.
pids=$tmp/pids
fake_running() {  # at least one fake started, and every one still runs
  [ -s "$pids" ] || return 1
  while read -r pid; do
    kill -0 "$pid" 2>/dev/null || return 1
  done <"$pids"
  return 0
}
no_fake_left() {  # at least one fake started, and none still runs
  [ -s "$pids" ] || return 1
  left=0
  while read -r pid; do
    if kill -0 "$pid" 2>/dev/null; then
      left=1
      kill -KILL "$pid" 2>/dev/null  # so a failed check leaves nothing behind
    fi
  done <"$pids"
  [ "$left" -eq 0 ]
}

marker='FAKE-MARKER-OK'

# The fake: counts its own starts in $FAKE_COUNTER (one line appended per
# invocation), writes its pid to $FAKE_PIDS (one line each too), and
# behaves according to $FAKE_PLAN. A 'hang' branch traps and ignores
# SIGTERM, as the real CCL does: a watchdog that sent SIGTERM instead of
# SIGKILL would hang against it.
fake=$tmp/fake-lisp
cat >"$fake" <<'FAKE'
#!/bin/sh
set -u
echo x >> "$FAKE_COUNTER"
echo $$ >> "$FAKE_PIDS"
n=$(wc -l < "$FAKE_COUNTER" | tr -d ' ')
case "$FAKE_PLAN" in
  hang)
    trap '' TERM
    while :; do sleep 1; done
    ;;
  hang-*)
    limit=${FAKE_PLAN#hang-}
    if [ "$n" -le "$limit" ]; then
      trap '' TERM
      while :; do sleep 1; done
    fi
    echo "$FAKE_MARKER"
    exit 0
    ;;
  marker-exit-*)
    status=${FAKE_PLAN#marker-exit-}
    echo "$FAKE_MARKER"
    exit "$status"
    ;;
  marker-sleep-exit-*)
    rest=${FAKE_PLAN#marker-sleep-exit-}
    secs=${rest%%-*}
    status=${rest#*-}
    echo "$FAKE_MARKER"
    sleep "$secs"
    exit "$status"
    ;;
  late-*)
    # Sleeps SECS, past the last poll of a short window but still inside
    # it, then prints the marker and exits 0 at once.
    secs=${FAKE_PLAN#late-}
    sleep "$secs"
    echo "$FAKE_MARKER"
    exit 0
    ;;
  fail-silent-*)
    status=${FAKE_PLAN#fail-silent-}
    exit "$status"
    ;;
  *)
    echo "fake-lisp: unknown FAKE_PLAN '$FAKE_PLAN'" >&2
    exit 9
    ;;
esac
FAKE
chmod +x "$fake"

# run_case PLAN WINDOW TRIES: runs the watchdog against the fake under
# PLAN, leaving $status (the watchdog's exit status), $starts (the
# fake's own count of how many times it was started), $pids (the pid of
# each start), and $tmp/out / $tmp/err (the watchdog's stdout/stderr) for
# the case below.
run_case() {
  counter=$tmp/counter
  : >"$counter"
  : >"$pids"
  FAKE_PLAN=$1 FAKE_COUNTER="$counter" FAKE_PIDS="$pids" FAKE_MARKER="$marker" \
    "$watchdog" "$2" "$3" "$marker" "$fake" \
    >"$tmp/out" 2>"$tmp/err" </dev/null
  status=$?
  starts=$(wc -l < "$counter" | tr -d ' ')
}

# C1: hangs silently twice, then prints the marker and exits 0: overall
# success, having started three times, with two restart messages.
run_case hang-2 2 3
check "C1 exit 0" [ "$status" -eq 0 ]
check "C1 three starts" [ "$starts" -eq 3 ]
retries=$(grep -c 'retrying' "$tmp/err")
check "C1 two restart messages" [ "$retries" -eq 2 ]

# C2: always hangs: failure after exactly TRIES starts, no more.
run_case hang 2 3
check "C2 non-zero exit" [ "$status" -ne 0 ]
check "C2 three starts" [ "$starts" -eq 3 ]

# C3: prints the marker, then exits 1: failure, with no retry.
run_case marker-exit-1 2 3
check "C3 exit 1" [ "$status" -eq 1 ]
check "C3 one start" [ "$starts" -eq 1 ]

# C4: prints the marker, then runs longer than the window, then exits 0:
# success, never killed (one start only; a kill would still let it exit
# 0, so the start count is what actually proves it was left alone).
# Plan is marker-sleep-exit-SECS-STATUS: sleeps 4s (> the 2s window),
# then exits 0.
run_case marker-sleep-exit-4-0 2 3
check "C4 exit 0" [ "$status" -eq 0 ]
check "C4 one start" [ "$starts" -eq 1 ]

# C5: exits non-zero before printing anything, as a load error would: no
# retry, and its exact status is passed on.
run_case fail-silent-7 2 3
check "C5 exit 7" [ "$status" -eq 7 ]
check "C5 one start" [ "$starts" -eq 1 ]

# C6: the marker lands at 1.6s of a 2s window -- past the last poll at
# 1s, but still inside the window. The last poll, right as the window
# closes, must still catch it: one start, no retry, exit 0.
run_case late-1.6 2 3
check "C6 exit 0" [ "$status" -eq 0 ]
check "C6 one start" [ "$starts" -eq 1 ]

# C7, C8: WINDOW and TRIES must each be a positive integer. Nothing is
# ever started when either is rejected.
for bad_window in abc 0 -1 1.5; do
  run_case marker-exit-0 "$bad_window" 3
  check "C7 rejects WINDOW '$bad_window'" [ "$status" -eq 2 ]
  check "C7 '$bad_window' starts nothing" [ "$starts" -eq 0 ]
done

for bad_tries in abc 0 -1 1.5; do
  run_case marker-exit-0 2 "$bad_tries"
  check "C8 rejects TRIES '$bad_tries'" [ "$status" -eq 2 ]
  check "C8 '$bad_tries' starts nothing" [ "$starts" -eq 0 ]
done

# C9: SIGTERM while the fake is hung, before its marker. The watchdog
# must SIGKILL it and exit at once, not just remove its work directory
# and keep waiting forever.
counter=$tmp/counter
: >"$counter"
: >"$pids"
FAKE_PLAN=hang FAKE_COUNTER="$counter" FAKE_PIDS="$pids" FAKE_MARKER="$marker" \
  "$watchdog" 10 3 "$marker" "$fake" >"$tmp/out" 2>"$tmp/err" </dev/null &
w=$!
sleep 1
check "C9 fake running before the signal" fake_running
kill -TERM "$w"
t0=$(date +%s); wait "$w"; status=$?; t1=$(date +%s)
check "C9 exit 143" [ "$status" -eq 143 ]
check "C9 returns promptly" [ "$((t1 - t0))" -le 3 ]
sleep 1
check "C9 leaves no fake running" no_fake_left

# C10: SIGTERM after the marker, with the run still going. The watchdog
# must SIGKILL it too, not leave it orphaned and running on its own.
: >"$counter"
: >"$pids"
FAKE_PLAN=marker-sleep-exit-10-0 FAKE_COUNTER="$counter" FAKE_PIDS="$pids" \
  FAKE_MARKER="$marker" \
  "$watchdog" 10 3 "$marker" "$fake" >"$tmp/out" 2>"$tmp/err" </dev/null &
w=$!
sleep 1
check "C10 fake running before the signal" fake_running
kill -TERM "$w"
t0=$(date +%s); wait "$w"; status=$?; t1=$(date +%s)
check "C10 exit 143" [ "$status" -eq 143 ]
check "C10 returns promptly" [ "$((t1 - t0))" -le 3 ]
sleep 1
check "C10 leaves no fake running" no_fake_left

# Not checked: a signal in an attempt's first moments, before the wrapper
# has recorded the run's pid, which on_signal waits for. The wrapper
# writes it right after forking the run, before the fake runs at all, so
# no fake can widen that window, and a test would hit it only by chance.

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
