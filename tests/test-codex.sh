#!/bin/sh
# Exercise the packaged launcher with a fake Codex CLI; never queue a live check.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
scripts="$here/../skills/clodBall/scripts"
launcher_source=${CLODBALL_CODEX:-"$scripts/clodball-codex"}
tmp=$(mktemp -d)
socket_dir=
cleanup() {
  if [ -n "$socket_dir" ]; then
    tmux -S "$socket_dir/s" kill-server 2>/dev/null || :
    rm -rf "$socket_dir"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
message_id=11111111-2222-3333-4444-555555555555

fail() {
  echo "FAIL: $*"
  exit 1
}

fixture() {
  thread=01234567-89ab-cdef-0123-456789abcdef
  case_dir="$tmp/$1"
  mkdir -p "$case_dir/bin" "$case_dir/skill/scripts" "$case_dir/state dir"
  [ -x "$launcher_source" ] || fail 'packaged launcher is missing or not executable'
  cp "$launcher_source" "$(dirname "$launcher_source")/clodball-watch" "$case_dir/skill/scripts/"
  launcher="$case_dir/skill/scripts/clodball-codex"
  handoff="$case_dir/shared \\backslash handoff.md"
  state_dir="$case_dir/state dir"
  printf '# Handoff\n\n## claude → cx: handled — 2000-01-01T00:00:00Z\n\nBall: cx\n' > "$handoff"
  cursor=$(wc -l < "$handoff" | tr -d '[:space:]')
  printf '%s\n' "$cursor" > "$state_dir/cursor.txt"
  export CODEX_TEST_CASE="$case_dir" CODEX_TEST_THREAD="$thread" CODEX_TEST_MESSAGE_ID="$message_id"
  export CLODBALL_ACK_TIMEOUT=0 CODEX_TEST_LAUNCHER="$launcher" CODEX_TEST_STATE="$state_dir"
  cat > "$case_dir/bin/sleep" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >> "$CODEX_TEST_CASE/sleeps"
exit 2
SH
  cat > "$case_dir/bin/codex" <<'SH'
#!/bin/sh
printf 'call\n' >> "$CODEX_TEST_CASE/calls"
printf '%s\n' "$@" > "$CODEX_TEST_CASE/args"
printf 'Queued message %s for thread %s.\n' "$CODEX_TEST_MESSAGE_ID" "$CODEX_TEST_THREAD"
SH
  chmod +x "$case_dir/bin/sleep" "$case_dir/bin/codex"
}

run_launcher() {
  if PATH="$case_dir/bin:$PATH" "$launcher" "$thread" "$handoff" "$cursor" "$state_dir" > "$case_dir/stdout" 2> "$case_dir/stderr"; then
    launch_status=0
  else
    launch_status=$?
  fi
}

ready() {
  printf '\n## claude → cx: review — 2000-01-01T00:00:01Z\n\nBall: cx\n' >> "$handoff"
}

expected_args() {
  expected_run=$(cat "$state_dir/current-run.txt")
  expected_launcher=$(cd "$(dirname "$launcher")" && pwd -P)/clodball-codex
  expected_message="\$clodBall check: new entry in $handoff
Before reading the snapshot, run: '$expected_launcher' ack started '$expected_run'
After successfully handling the snapshot and saving its cursor, before re-arming, run: '$expected_launcher' ack handled '$expected_run'"
  printf '%s\n' queue --thread "$1" --message "$expected_message" > "$case_dir/expected-args"
}

success() {
  fixture success
  launcher=$launcher_source
  # The real watcher first sees only handled entries. Its first poll appends
  # a peer request through a fake sleep, so this also proves the default interval.
  export CODEX_TEST_HANDOFF="$handoff"
  cat > "$case_dir/bin/sleep" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >> "$CODEX_TEST_CASE/sleeps"
[ ! -e "$CODEX_TEST_CASE/expected-handoff" ] || exit 2
printf '\n## claude → cx: review — 2000-01-01T00:00:01Z\n\nAsk: inspect the artifact\nBall: cx\n' >> "$CODEX_TEST_HANDOFF"
cp "$CODEX_TEST_HANDOFF" "$CODEX_TEST_CASE/expected-handoff"
SH
  chmod +x "$case_dir/bin/sleep"
  run_launcher
  [ "$launch_status" -eq 0 ] || fail "valid handoff exited $launch_status: $(cat "$case_dir/stderr")"
  [ "$(cat "$state_dir/phase.txt")" = queued ] || fail 'valid check is not marked queued'
  [ "$(cat "$case_dir/calls")" = call ] || fail 'launcher did not queue exactly once'
  [ "$(cat "$case_dir/sleeps")" = 30 ] || fail 'watcher did not use its default interval exactly once'
  expected_args "$thread"
  cmp -s "$case_dir/expected-args" "$case_dir/args" || fail 'queued check has wrong arguments'
  cmp -s "$case_dir/expected-handoff" "$handoff" || fail 'launcher changed the handoff'
  [ "$(cat "$state_dir/cursor.txt")" = "$cursor" ] || fail 'launcher advanced the saved cursor'
  echo 'ok: real watcher uses the saved cursor and default interval, queues one exact check, and preserves handoff and cursor'
}

watcher_failure() {
  fixture watcher-failure
  rm "$handoff"
  run_launcher
  [ "$launch_status" -eq 2 ] || fail "failed watcher exited $launch_status instead of 2"
  [ "$(cat "$state_dir/phase.txt")" = watcher-failed ] || fail 'watcher failure did not update its phase'
  [ -s "$state_dir/wake.err" ] || fail 'watcher diagnostic was lost'
  [ ! -e "$case_dir/calls" ] || fail 'failed watcher still queued a check'
  echo 'ok: watcher failure keeps its diagnostic and exit status, reports failure, and queues nothing'
}

watcher_receipt() {
  fixture watcher-receipt
  cat > "$case_dir/skill/scripts/clodball-watch" <<'SH'
#!/bin/sh
printf 'clodball: new entry for cx in %s\nextra output\n' "$2"
SH
  run_launcher
  [ "$launch_status" -eq 2 ] || fail "malformed watcher receipt exited $launch_status instead of 2"
  [ "$(cat "$state_dir/phase.txt")" = invalid-wake-output ] || fail 'malformed watcher receipt is not reported'
  [ -s "$state_dir/wake.out" ] || fail 'malformed watcher receipt was lost'
  [ ! -e "$case_dir/calls" ] || fail 'malformed watcher receipt still queued a check'
  echo 'ok: extra watcher output is retained and refused before queuing'
}

queue_failure() {
  fixture queue-failure
  ready
  cat > "$case_dir/bin/codex" <<'SH'
#!/bin/sh
printf 'call\n' >> "$CODEX_TEST_CASE/calls"
echo 'queue transport failed' >&2
exit 7
SH
  run_launcher
  [ "$launch_status" -eq 7 ] || fail "failed Codex queue exited $launch_status instead of 7"
  [ "$(cat "$state_dir/phase.txt")" = queue-failed ] || fail 'Codex queue failure did not update its phase'
  [ "$(cat "$state_dir/queue.err")" = 'queue transport failed' ] || fail 'queue diagnostic was lost'
  [ "$(cat "$case_dir/calls")" = call ] || fail 'launcher retried the failed queue'
  echo 'ok: queue failure retains its diagnostic and exit status, reports failure, and does not retry'
}

queue_receipt() {
  for receipt_case in wrong-thread extra-output malformed-id empty missing-newline; do
    fixture "queue-receipt-$receipt_case"
    ready
    export CODEX_TEST_RECEIPT="$receipt_case"
    cat > "$case_dir/bin/codex" <<'SH'
#!/bin/sh
printf 'call\n' >> "$CODEX_TEST_CASE/calls"
case "$CODEX_TEST_RECEIPT" in
  wrong-thread) printf 'Queued message %s for thread %s.\n' "$CODEX_TEST_MESSAGE_ID" "$CODEX_TEST_MESSAGE_ID" ;;
  extra-output) printf 'Queued message %s for thread %s.\nextra output' "$CODEX_TEST_MESSAGE_ID" "$CODEX_TEST_THREAD" ;;
  malformed-id) printf 'Queued message not-an-id for thread %s.\n' "$CODEX_TEST_THREAD" ;;
  empty) ;;
  missing-newline) printf 'Queued message %s for thread %s.' "$CODEX_TEST_MESSAGE_ID" "$CODEX_TEST_THREAD" ;;
esac
SH
    run_launcher
    [ "$launch_status" -eq 2 ] || fail "$receipt_case queue receipt exited $launch_status instead of 2"
    [ "$(cat "$state_dir/phase.txt")" = queue-outcome-uncertain ] || fail "$receipt_case queue receipt is not marked uncertain"
    [ -f "$state_dir/queue.out" ] || fail "$receipt_case queue receipt was lost"
    [ "$(cat "$case_dir/calls")" = call ] || fail "$receipt_case queue receipt caused a retry"
  done
  echo 'ok: unexpected queue confirmations remain uncertain and are retained without retries'
}

state_reuse() {
  fixture state-reuse
  ready
  run_launcher
  [ "$launch_status" -eq 0 ] || fail 'initial launch did not queue a check'
  [ -s "$state_dir/queue.out" ] || fail 'initial launch left no queue receipt'
  [ -s "$state_dir/current-run.txt" ] || fail 'initial launch left no archive identity'
  first_run=$(cat "$state_dir/current-run.txt")
  cp "$first_run/queue.out" "$case_dir/first-receipt"
  [ -s "$first_run/created-at.txt" ] || fail 'archive has no creation timestamp'
  rm "$handoff"
  run_launcher
  [ "$launch_status" -eq 2 ] || fail 'second launch did not report watcher failure'
  [ "$(cat "$state_dir/phase.txt")" = watcher-failed ] || fail 'second launch retained an old phase'
  [ ! -s "$state_dir/queue.out" ] || fail 'failed new launch retained an old queue confirmation'
  [ ! -s "$state_dir/queue.err" ] || fail 'failed new launch retained an old queue diagnostic'
  [ ! -e "$state_dir/expected-queue.txt" ] || fail 'failed new launch retained an old expected confirmation'
  [ "$(cat "$case_dir/calls")" = call ] || fail 'second launch queued another check'
  [ "$(cat "$state_dir/current-run.txt")" != "$first_run" ] || fail 'second launch reused an archive'
  cmp -s "$first_run/queue.out" "$case_dir/first-receipt" || fail 'rearm destroyed the archived queue receipt'
  echo 'ok: a reused state directory clears the latest view and preserves timestamped launch archives'
}

acknowledgements() {
  fixture acknowledgements
  ready
  run_launcher
  [ "$launch_status" -eq 0 ] || fail 'initial launch failed'
  first_run=$(cat "$state_dir/current-run.txt")
  if "$launcher" ack handled "$first_run" > "$case_dir/ack.out" 2> "$case_dir/ack.err"; then
    fail 'handled without started was accepted'
  fi
  [ ! -e "$first_run/handled-at.txt" ] || fail 'refused handled acknowledgement wrote a receipt'
  "$launcher" ack started "$first_run" || fail 'started acknowledgement was refused'
  [ -s "$first_run/started-at.txt" ] || fail 'started acknowledgement has no timestamp'
  printf '2000-01-01T00:00:00Z\n' > "$first_run/started-at.txt"
  "$launcher" ack started "$first_run" || fail 'repeated started acknowledgement was refused'
  [ "$(cat "$first_run/started-at.txt")" = '2000-01-01T00:00:00Z' ] || fail 'repeated acknowledgement replaced the first timestamp'
  "$launcher" ack handled "$first_run" || fail 'handled after started was refused'
  [ -s "$first_run/handled-at.txt" ] || fail 'handled acknowledgement has no timestamp'
  run_launcher
  second_run=$(cat "$state_dir/current-run.txt")
  "$launcher" ack started "$first_run" || fail 'late acknowledgement was refused'
  [ ! -e "$second_run/started-at.txt" ] || fail 'old acknowledgement marked the newer launch started'
  [ -s "$second_run/alert.txt" ] || fail 'old acknowledgement silenced the newer launch watchdog'
  if "$launcher" ack started "$case_dir/unknown" > "$case_dir/ack.out" 2> "$case_dir/ack.err"; then
    fail 'unknown run was accepted'
  fi
  [ ! -e "$case_dir/unknown" ] || fail 'unknown acknowledgement created state'
  [ "$(wc -l < "$case_dir/calls" | tr -d '[:space:]')" -eq 2 ] || fail 'acknowledgements queued another check'
  echo 'ok: acknowledgements preserve first timestamps, require started before handled, and target only their own launch'
}

uncertain_acknowledgements() {
  fixture uncertain-acknowledgements
  ready
  cat > "$case_dir/bin/codex" <<'SH'
#!/bin/sh
printf 'call\n' >> "$CODEX_TEST_CASE/calls"
printf 'unexpected queue confirmation\n'
SH
  run_launcher
  [ "$launch_status" -eq 2 ] || fail 'unexpected receipt was not marked uncertain'
  run_dir=$(cat "$state_dir/current-run.txt")
  "$launcher" ack started "$run_dir" || fail 'uncertain receipt prevented a later started acknowledgement'
  "$launcher" ack handled "$run_dir" || fail 'uncertain receipt prevented a later handled acknowledgement'
  [ -s "$run_dir/started-at.txt" ] && [ -s "$run_dir/handled-at.txt" ] || fail 'late acknowledgement receipts were lost'
  [ "$(cat "$run_dir/phase.txt")" = queue-outcome-uncertain ] || fail 'acknowledgement replaced the uncertain queue phase'
  [ "$(cat "$case_dir/calls")" = call ] || fail 'uncertain acknowledgement caused a queue retry'
  echo 'ok: late acknowledgements survive an uncertain queue receipt without changing its phase or retrying'
}

watchdog() {
  fixture watchdog-missing
  ready
  CLODBALL_ACK_TIMEOUT=30
  export CLODBALL_ACK_TIMEOUT
  printf '100\n' > "$case_dir/clock"
  cat > "$case_dir/bin/date" <<'SH'
#!/bin/sh
if [ "$1" = +%s ]; then cat "$CODEX_TEST_CASE/clock"; else /bin/date "$@"; fi
SH
  cat > "$case_dir/bin/sleep" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >> "$CODEX_TEST_CASE/sleeps"
printf '130\n' > "$CODEX_TEST_CASE/clock"
SH
  chmod +x "$case_dir/bin/date" "$case_dir/bin/sleep"
  run_launcher
  [ "$launch_status" -eq 0 ] || fail 'watchdog changed the successful queue exit status'
  run_dir=$(cat "$state_dir/current-run.txt")
  [ -s "$run_dir/alert.txt" ] || fail 'missing acknowledgement was not flagged'
  [ -s "$run_dir/queued-at.txt" ] || fail 'queue has no timestamp'
  grep -Fq 'no started acknowledgement' "$case_dir/stderr" || fail 'missing acknowledgement produced no warning'
  [ "$(cat "$case_dir/sleeps")" = 30 ] || fail 'watchdog did not use a bounded poll'
  [ "$(cat "$case_dir/calls")" = call ] || fail 'watchdog resent the check'

  fixture watchdog-poll-started
  ready
  export CLODBALL_ACK_TIMEOUT=30
  printf '100\n' > "$case_dir/clock"
  cp "$tmp/watchdog-missing/bin/date" "$case_dir/bin/date"
  cat > "$case_dir/bin/sleep" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >> "$CODEX_TEST_CASE/sleeps"
run_dir=$(cat "$CODEX_TEST_STATE/current-run.txt")
"$CODEX_TEST_LAUNCHER" ack started "$run_dir"
printf '130\n' > "$CODEX_TEST_CASE/clock"
SH
  run_launcher
  [ "$launch_status" -eq 0 ] || fail 'start during polling failed'
  run_dir=$(cat "$state_dir/current-run.txt")
  [ -s "$run_dir/started-at.txt" ] || fail 'start during polling was lost'
  [ ! -e "$run_dir/alert.txt" ] || fail 'start during polling produced a deadline alert'
  [ ! -s "$case_dir/stderr" ] || fail 'start during polling produced a warning'
  [ "$(cat "$case_dir/sleeps")" = 30 ] || fail 'start during polling did not traverse a poll'
  [ "$(cat "$case_dir/clock")" = 130 ] || fail 'start during polling did not reach the deadline'
  [ "$(cat "$case_dir/calls")" = call ] || fail 'start during polling caused a resend'

  fixture watchdog-started
  ready
  cat > "$case_dir/bin/codex" <<'SH'
#!/bin/sh
printf 'call\n' >> "$CODEX_TEST_CASE/calls"
run_dir=$(cat "$CODEX_TEST_STATE/current-run.txt")
"$CODEX_TEST_LAUNCHER" ack started "$run_dir"
printf 'Queued message %s for thread %s.\n' "$CODEX_TEST_MESSAGE_ID" "$CODEX_TEST_THREAD"
SH
  run_launcher
  [ "$launch_status" -eq 0 ] || fail 'acknowledged queue failed'
  run_dir=$(cat "$state_dir/current-run.txt")
  [ -s "$run_dir/started-at.txt" ] || fail 'early started acknowledgement was lost'
  [ ! -e "$run_dir/alert.txt" ] || fail 'acknowledged check was flagged'
  [ ! -s "$case_dir/stderr" ] || fail 'acknowledged check produced a warning'
  [ ! -e "$case_dir/sleeps" ] || fail 'watchdog slept after seeing started'
  [ "$(cat "$case_dir/calls")" = call ] || fail 'acknowledged check was resent'
  echo 'ok: watchdog flags a missing start after elapsed time, stays quiet for a start, and never resends'
}

tmux_rearm() {
  fixture tmux-rearm
  ready
  rm "$case_dir/bin/sleep"
  unset CLODBALL_ACK_TIMEOUT
  # Pin the fake CLI after tmux's startup shell has applied its environment.
  export CODEX_TEST_BASE_PATH="$PATH"
  tmux_launcher="$case_dir/tmux-launcher"
  cat > "$tmux_launcher" <<'SH'
#!/bin/sh
set -eu
PATH="$CODEX_TEST_CASE/bin:$CODEX_TEST_BASE_PATH"
export PATH
[ "$(command -v codex)" = "$CODEX_TEST_CASE/bin/codex" ] || exit 2
exec "$CODEX_TEST_LAUNCHER" "$@"
SH
  chmod +x "$tmux_launcher"
  # A separate, short socket path owns every process; never use the user's server.
  socket_dir=$(mktemp -d /tmp/clodball-tmux.XXXXXX)
  PATH="$case_dir/bin:$PATH" tmux -S "$socket_dir/s" -f /dev/null new-session \
    -d -s clodball -n watcher "$tmux_launcher" "$thread" "$handoff" "$cursor" "$state_dir"
  owned_window=$(tmux -S "$socket_dir/s" display-message -p -t clodball:watcher '#{window_id}')
  first_pid=$(tmux -S "$socket_dir/s" display-message -p -t "$owned_window" '#{pane_pid}')
  wait_for_run() {
    attempt=0
    while [ "$attempt" -lt 30 ]; do
      run_dir=
      [ ! -s "$state_dir/current-run.txt" ] || run_dir=$(cat "$state_dir/current-run.txt")
      if [ -n "$run_dir" ] && [ "$run_dir" != "${previous_run:-}" ] && [ -s "$run_dir/queued-at.txt" ]; then return; fi
      sleep 0.1
      attempt=$((attempt + 1))
    done
    fake_calls=0
    [ ! -f "$case_dir/calls" ] || fake_calls=$(wc -l < "$case_dir/calls" | tr -d '[:space:]')
    fail "owned tmux window did not queue ${previous_run:+the next }launch (fake CLI calls: $fake_calls)"
  }
  wait_for_run
  [ "$(cat "$case_dir/calls")" = call ] || fail 'first tmux launch did not use the fake Codex CLI'
  first_run=$run_dir
  cp "$first_run/queue.out" "$case_dir/first-receipt"
  sleeping=no
  attempt=0
  while [ "$attempt" -lt 30 ]; do
    if pgrep -P "$first_pid" -x sleep > /dev/null; then sleeping=yes; break; else
      result=$?
      [ "$result" -eq 1 ] || fail 'cannot inspect owned watchdog sleep'
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done
  [ "$sleeping" = yes ] || fail 'first watchdog never entered its real polling sleep'
  "$launcher" ack started "$first_run"
  cp "$handoff" "$case_dir/snapshot"
  saved_cursor=$(wc -l < "$case_dir/snapshot" | tr -d '[:space:]')
  printf '%s\n' "$saved_cursor" > "$state_dir/cursor.txt"
  "$launcher" ack handled "$first_run"
  cp "$first_run/started-at.txt" "$case_dir/first-started"
  cp "$first_run/handled-at.txt" "$case_dir/first-handled"
  printf '\n## claude → cx: next review — 2000-01-01T00:00:02Z\n\nBall: cx\n' >> "$handoff"
  previous_run=$first_run
  tmux -S "$socket_dir/s" respawn-window -k -t "$owned_window" \
    "$tmux_launcher" "$thread" "$handoff" "$saved_cursor" "$state_dir"
  wait_for_run
  [ "$(wc -l < "$case_dir/calls" | tr -d '[:space:]')" -eq 2 ] || fail 'tmux rearm did not queue exactly once per run'
  [ "$(cat "$state_dir/cursor.txt")" = "$saved_cursor" ] || fail 'tmux rearm advanced the saved snapshot cursor'
  cmp -s "$first_run/queue.out" "$case_dir/first-receipt" || fail 'tmux rearm changed the archived receipt'
  cmp -s "$first_run/started-at.txt" "$case_dir/first-started" || fail 'tmux rearm changed the started acknowledgement'
  cmp -s "$first_run/handled-at.txt" "$case_dir/first-handled" || fail 'tmux rearm changed the handled acknowledgement'
  second_pid=$(tmux -S "$socket_dir/s" display-message -p -t "$owned_window" '#{pane_pid}')
  [ "$first_pid" != "$second_pid" ] || fail 'tmux rearm reused the sleeping monitor process'
  wait_stopped() {
    attempt=0
    while [ "$attempt" -lt 30 ]; do
      if ! kill -0 "$1" 2>/dev/null; then return; fi
      sleep 0.1
      attempt=$((attempt + 1))
    done
    fail 'owned launcher survived tmux replacement or stop'
  }
  wait_stopped "$first_pid"
  tmux -S "$socket_dir/s" kill-server
  wait_stopped "$second_pid"
  rm -rf "$socket_dir"
  socket_dir=
  echo 'ok: real tmux rearm replaces a sleeping monitor, queues the next unread entry once, preserves receipts and cursor, and stops owned launchers'
}

invalid_thread() {
  fixture invalid-thread
  ready
  thread=not-a-thread-uuid
  run_launcher
  [ "$launch_status" -eq 2 ] || fail 'invalid thread was not refused with exit 2'
  [ "$(cat "$state_dir/phase.txt")" = invalid-arguments ] || fail 'invalid thread is not marked invalid arguments'
  [ ! -e "$case_dir/calls" ] || fail 'invalid thread reached Codex queue'
  [ -s "$case_dir/stderr" ] || fail 'invalid thread produced no diagnostic'
  echo 'ok: an invalid thread is refused before starting a watcher or queue'
}

uppercase_thread() {
  fixture uppercase-thread
  ready
  lowercase_thread=$thread
  thread=01234567-89AB-CDEF-0123-456789ABCDEF
  run_launcher
  [ "$launch_status" -eq 0 ] || fail 'a canonical confirmation for an uppercase thread was refused'
  [ "$(cat "$state_dir/phase.txt")" = queued ] || fail 'uppercase thread was not marked queued'
  expected_args "$lowercase_thread"
  cmp -s "$case_dir/expected-args" "$case_dir/args" || fail 'uppercase thread was not normalized before queueing'
  [ "$(cat "$case_dir/calls")" = call ] || fail 'uppercase thread caused a queue retry'
  echo 'ok: uppercase thread UUIDs use canonical lowercase for the queue and its confirmation'
}

unexpected_poll() {
  fixture unexpected-poll
  run_launcher
  [ "$launch_status" -eq 2 ] || fail 'unexpected polling was not stopped'
  [ "$(cat "$state_dir/phase.txt")" = watcher-failed ] || fail 'unexpected polling did not report watcher failure'
  [ "$(cat "$case_dir/sleeps")" = 30 ] || fail 'unexpected polling did not stop on its first sleep'
  [ ! -e "$case_dir/calls" ] || fail 'unexpected polling still queued a check'
  echo 'ok: unexpected polling fails immediately in the fixture instead of sleeping indefinitely'
}

invalid_rearm() {
  for invalid_argument in thread cursor; do
    fixture "invalid-rearm-$invalid_argument"
    ready
    run_launcher
    [ "$launch_status" -eq 0 ] || fail 'initial launch did not queue a check'
    case "$invalid_argument" in
      thread) thread=not-a-thread-uuid ;;
      cursor) cursor=not-a-cursor ;;
    esac
    run_launcher
    [ "$launch_status" -eq 2 ] || fail "invalid $invalid_argument re-arm was not refused"
    [ "$(cat "$state_dir/phase.txt")" = invalid-arguments ] || fail "invalid $invalid_argument re-arm retained an old phase"
    [ ! -s "$state_dir/wake.out" ] || fail "invalid $invalid_argument re-arm retained an old wake receipt"
    [ ! -s "$state_dir/queue.out" ] || fail "invalid $invalid_argument re-arm retained an old queue receipt"
    [ ! -e "$state_dir/expected-queue.txt" ] || fail "invalid $invalid_argument re-arm retained an old expected confirmation"
    [ "$(cat "$case_dir/calls")" = call ] || fail "invalid $invalid_argument re-arm queued a check"
  done
  echo 'ok: invalid re-arms clear prior receipts and report invalid arguments without another queue'
}

case "${1:-all}" in
  success) success ;;
  watcher-failure) watcher_failure ;;
  watcher-receipt) watcher_receipt ;;
  queue-failure) queue_failure ;;
  queue-receipt) queue_receipt ;;
  state-reuse) state_reuse ;;
  acknowledgements) acknowledgements ;;
  uncertain-acknowledgements) uncertain_acknowledgements ;;
  watchdog) watchdog ;;
  tmux-rearm) tmux_rearm ;;
  invalid-thread) invalid_thread ;;
  uppercase-thread) uppercase_thread ;;
  unexpected-poll) unexpected_poll ;;
  invalid-rearm) invalid_rearm ;;
  all) success; watcher_failure; watcher_receipt; queue_failure; queue_receipt; state_reuse; acknowledgements; uncertain_acknowledgements; watchdog; tmux_rearm; invalid_thread; uppercase_thread; unexpected_poll; invalid_rearm ;;
  *) fail "unknown test: $1" ;;
esac
