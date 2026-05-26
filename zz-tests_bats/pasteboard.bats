# bats file_tags=pasteboard

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  setup_test_home
  setup_test_pasteboard
}

teardown() {
  teardown_test_home
}

@test "copy + paste round-trips plain text through a named pasteboard" {
  run_tacky_with_stdin "hello, tacky" \
    --pasteboard "$TACKY_TEST_PB" copy -i public.utf8-plain-text -
  assert_success

  run_tacky --pasteboard "$TACKY_TEST_PB" paste -u public.utf8-plain-text
  assert_success
  assert_output "hello, tacky"
}

@test "paste --list reports the UTI a fresh write declared" {
  run_tacky_with_stdin "<p>hi</p>" \
    --pasteboard "$TACKY_TEST_PB" copy -i public.html -
  assert_success

  run_tacky --pasteboard "$TACKY_TEST_PB" paste --list
  assert_success
  assert_line "public.html"
}

@test "paste -u for an absent UTI exits 1 with a stderr message" {
  run_tacky_with_stdin "x" \
    --pasteboard "$TACKY_TEST_PB" copy -i public.utf8-plain-text -
  assert_success

  run_tacky --pasteboard "$TACKY_TEST_PB" paste -u public.html
  assert_failure 1
  assert_output --partial "no item on pasteboard"
}

@test "copy declares multiple UTIs in one invocation and both readback" {
  run_tacky_with_stdin "shared-payload" \
    --pasteboard "$TACKY_TEST_PB" copy \
    -i public.utf8-plain-text - \
    -i public.html -
  assert_success

  run_tacky --pasteboard "$TACKY_TEST_PB" paste -u public.utf8-plain-text
  assert_success

  run_tacky --pasteboard "$TACKY_TEST_PB" paste -u public.html
  assert_success
}

@test "two named pasteboards stay isolated" {
  local pb_a="${TACKY_TEST_PB}-a"
  local pb_b="${TACKY_TEST_PB}-b"

  run_tacky_with_stdin "from-a" --pasteboard "$pb_a" copy -i public.utf8-plain-text -
  assert_success
  run_tacky_with_stdin "from-b" --pasteboard "$pb_b" copy -i public.utf8-plain-text -
  assert_success

  run_tacky --pasteboard "$pb_a" paste -u public.utf8-plain-text
  assert_success
  assert_output "from-a"

  run_tacky --pasteboard "$pb_b" paste -u public.utf8-plain-text
  assert_success
  assert_output "from-b"
}

@test "paste --list on an unused pasteboard prints nothing and exits 0" {
  run_tacky --pasteboard "${TACKY_TEST_PB}-unused" paste --list
  assert_success
  assert_output ""
}
