#! /bin/bash -e
#
# zz-tests_bats/common.bash — load this from every .bats file's setup():
#
#   setup() {
#     load "$(dirname "$BATS_TEST_FILE")/common.bash"
#     setup_test_home
#     setup_test_pasteboard
#   }

if [[ -z $BATS_TEST_TMPDIR ]]; then
  echo 'common.bash loaded before $BATS_TEST_TMPDIR set. aborting.' >&2
  exit 1
fi

pushd "$BATS_TEST_TMPDIR" >/dev/null || exit 1

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-emo
bats_load_library bats-island

require_bin TACKY_BIN tacky

# Per-test wrapper around the tacky binary. Sets a 2-second per-invocation
# wall-clock cap (independent of BATS_TEST_TIMEOUT, which caps the whole
# @test block) so a hung call doesn't eat the entire test budget.
#
# Important: do NOT pipe into `run_tacky` (e.g. `echo x | run_tacky ...`),
# because bash pipelines run the right-hand side in a subshell — the
# `output`/`status` variables that bats's `run` sets there don't
# propagate back to the test, and assert_success will fail with
# `output: parameter not set`. For tests that need to send data on
# stdin, use `run_tacky_with_stdin` (below).
run_tacky() {
  local bin="${TACKY_BIN:-tacky}"
  run timeout --preserve-status 2s "$bin" "$@"
}

# Same as run_tacky, but reads the first argument as the stdin payload
# and forwards the rest to the binary. Uses a redirect on `run` itself
# so `output`/`status` are set in the test's shell, not a pipeline
# subshell.
#
# Usage: run_tacky_with_stdin "<payload>" <args...>
run_tacky_with_stdin() {
  local bin="${TACKY_BIN:-tacky}"
  local payload="$1"
  shift
  local stdin_file="$BATS_TEST_TMPDIR/stdin-$$"
  printf '%s' "$payload" > "$stdin_file"
  run timeout --preserve-status 2s "$bin" "$@" < "$stdin_file"
}

# Allocate a uniquely-named pasteboard for this test. Each test gets its
# own isolated NSPasteboard, so tests can run in parallel without
# clobbering each other and never touch the user's real clipboard.
#
# macOS creates pasteboards lazily on first access via
# `pasteboardWithName:`, so we don't need to pre-create anything; we
# just pick a name. Pasteboard names are visible to other processes on
# the same user session, so include $BATS_TEST_TMPDIR's basename for
# isolation across concurrent bats runs.
#
# Note: named pasteboards persist in the per-user pboard server until
# explicitly released. We intentionally do NOT release in teardown
# because the macOS pboard server reaps stale entries on its own and a
# straggling pasteboard from a killed test is harmless. Bumping the
# unique seed each run keeps history-bleed bounded.
setup_test_pasteboard() {
  local seed
  seed="$(basename "$BATS_TEST_TMPDIR")-${BATS_TEST_NUMBER:-0}-$$"
  export TACKY_TEST_PB="tacky-bats-${seed}"
}
