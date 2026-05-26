# bats file_tags=help

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  setup_test_home
}

teardown() {
  teardown_test_home
}

@test "tacky --help prints synopsis and the copy + paste subcommands" {
  run_tacky --help
  assert_success
  assert_line --regexp '^Usage: tacky'
  assert_line --partial "copy"
  assert_line --partial "paste"
  assert_line --partial "--pasteboard"
}

@test "tacky copy --help mentions the -i UTI FILE form" {
  run_tacky copy --help
  assert_success
  assert_line --partial "UTI"
  assert_line --partial "FILE"
}

@test "tacky paste --help mentions --uti and --list" {
  run_tacky paste --help
  assert_success
  assert_line --partial "--uti"
  assert_line --partial "--list"
}
