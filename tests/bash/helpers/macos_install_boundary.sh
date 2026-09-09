#!/usr/bin/env bash
# Host-only operations replaced at the macOS installer integration boundary.
if [[ ${DOTFILES_TEST_HOMEBREW_UNAVAILABLE:-0} == 1 ]]; then
  homebrew_command() {
    [[ -f $FAKE_DOCKER_CASK_STATE ]] || return 1
    printf '%s\n' "$DOTFILES_BREW_COMMAND"
  }
fi
ensure_docker_desktop_md5_compatibility() {
  :
}
homebrew_cask_link_parent_metadata() {
  printf '%s\n' "$TEST_HOMEBREW_PARENT_METADATA"
}
homebrew_cask_link_parent_acl_state() {
  printf '%s\n' "$TEST_HOMEBREW_PARENT_ACL_STATE"
}
homebrew_cask_link_parent_is_immutable_to_caller() {
  [[ $TEST_HOMEBREW_PARENT_IMMUTABLE_TO_CALLER == 1 ]]
}
