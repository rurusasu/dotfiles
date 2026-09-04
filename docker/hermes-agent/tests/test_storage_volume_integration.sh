#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
fixture_dir="$(mktemp -d)"
volume_name="hermes-storage-integration-$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
lock_name=""

cleanup() {
  if [[ -n $lock_name ]]; then
    docker rm -f "$lock_name" >/dev/null 2>&1 || true
  fi
  docker volume rm "$volume_name" >/dev/null 2>&1 || true
  rm -r "$fixture_dir"
}
trap cleanup EXIT

FIXTURE_DIR="$fixture_dir" python3 - <<'PY'
import os
import sqlite3
from pathlib import Path

root = Path(os.environ["FIXTURE_DIR"])
(root / "nested").mkdir()
(root / "config.yaml").write_text("profile: integration\n", encoding="utf-8")
with sqlite3.connect(root / "state?#%.db") as database:
    database.execute("create table checks (value text not null)")
    database.execute("insert into checks values ('atomic-ready')")
(root / "nested" / "config-link").symlink_to("../config.yaml")
PY

# shellcheck source=../../../scripts/sh/install-common.sh
source "$repository_root/scripts/sh/install-common.sh"
# shellcheck source=../../../scripts/sh/hermes-agent.sh
source "$repository_root/scripts/sh/hermes-agent.sh"
export HERMES_DATA_DIR="$fixture_dir"
export HERMES_DATA_VOLUME="$volume_name"

dotfiles_hermes_initialize_storage_volume docker
volume_token="$(docker volume inspect --format '{{ index .Labels "com.rurusasu.dotfiles.hermes-storage.init-token" }}' "$volume_name")"
lock_name="$(dotfiles_hermes_storage_lock_name "$volume_name")"

docker run -d --rm \
  --name "$lock_name" \
  --entrypoint sleep \
  --mount "type=volume,src=$volume_name,dst=/locked,readonly" \
  local/hermes-agent-gh:latest \
  21600 >/dev/null
if docker volume rm "$volume_name" >/dev/null 2>&1; then
  printf 'volume deletion unexpectedly succeeded while guarded\n' >&2
  exit 1
fi
if dotfiles_hermes_initialize_storage_volume docker >/dev/null 2>&1; then
  printf 'a second initializer unexpectedly acquired the guard\n' >&2
  exit 1
fi
docker rm -f "$lock_name" >/dev/null
lock_name=""

docker run --rm \
  --entrypoint sh \
  --mount "type=volume,src=$volume_name,dst=/target" \
  local/hermes-agent-gh:latest \
  -c 'printf "spoofed\n" > /target/.dotfiles-hermes-storage-ready-v1'
dotfiles_hermes_initialize_storage_volume docker

ln -s ../../outside "$fixture_dir/nested/bad-link"
docker run --rm \
  --entrypoint sh \
  --mount "type=volume,src=$volume_name,dst=/target" \
  local/hermes-agent-gh:latest \
  -c 'printf "invalid\n" > /target/.dotfiles-hermes-storage-ready-v1'
if dotfiles_hermes_initialize_storage_volume docker >/dev/null 2>&1; then
  printf 'an unsafe source symlink unexpectedly seeded\n' >&2
  exit 1
fi
[[ "$(docker volume inspect --format '{{ index .Labels "com.rurusasu.dotfiles.hermes-storage.init-token" }}' "$volume_name")" == "$volume_token" ]]
[[ -z "$(docker ps -aq --filter "name=^/$(dotfiles_hermes_storage_lock_name "$volume_name")$")" ]]

lock_name="$(dotfiles_hermes_storage_lock_name "$volume_name")"
docker create \
  --name "$lock_name" \
  --label "com.rurusasu.dotfiles.hermes-storage.lock=1" \
  --label "com.rurusasu.dotfiles.hermes-storage.init-token=$volume_token" \
  --entrypoint /usr/local/bin/hermes-storage-seed \
  --mount "type=bind,src=$fixture_dir,dst=/source,readonly" \
  --mount "type=volume,src=$volume_name,dst=/target" \
  local/hermes-agent-gh:latest \
  --source /source --destination /target \
  --ready-token "$volume_token" --replace-incomplete >/dev/null
if docker start -a "$lock_name" >/dev/null 2>&1; then
  printf 'the intentionally invalid stale-lock seed unexpectedly succeeded\n' >&2
  exit 1
fi
[[ "$(docker inspect --format '{{ .State.Status }}' "$lock_name")" == exited ]]
unlink "$fixture_dir/nested/bad-link"

dotfiles_hermes_initialize_storage_volume docker
lock_name=""

lock_name="$(dotfiles_hermes_storage_lock_name "$volume_name")"
stale_created_id="$(docker create \
  --name "$lock_name" \
  --label "com.rurusasu.dotfiles.hermes-storage.lock=1" \
  --label "com.rurusasu.dotfiles.hermes-storage.init-token=$volume_token" \
  --label "com.rurusasu.dotfiles.hermes-storage.lock-created-at=0" \
  --entrypoint /usr/local/bin/hermes-storage-seed \
  --mount "type=bind,src=$fixture_dir,dst=/source,readonly" \
  --mount "type=volume,src=$volume_name,dst=/target" \
  local/hermes-agent-gh:latest \
  --source /source --destination /target \
  --ready-token "$volume_token" --replace-incomplete)"
dotfiles_hermes_initialize_storage_volume docker
if docker inspect "$stale_created_id" >/dev/null 2>&1; then
  printf 'an aged created lock was not reclaimed by immutable ID\n' >&2
  exit 1
fi
lock_name=""

dotfiles_hermes_initialize_storage_volume docker

marker="$(docker run --rm \
  --entrypoint sh \
  --mount "type=volume,src=$volume_name,dst=/target,readonly" \
  local/hermes-agent-gh:latest \
  -c 'cat /target/.dotfiles-hermes-storage-ready-v1')"
row="$(docker run --rm \
  --entrypoint python \
  --mount "type=volume,src=$volume_name,dst=/target,readonly" \
  local/hermes-agent-gh:latest \
  -c 'import sqlite3; print(sqlite3.connect("/target/state?#%.db").execute("select value from checks").fetchone()[0])')"

[[ $marker == $'version=1\nvolume_token='"$volume_token" ]]
[[ $row == atomic-ready ]]
printf 'Hermes storage volume integration passed.\n'
