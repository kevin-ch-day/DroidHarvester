#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cp -a "$ROOT" "$workdir/repo"
cd "$workdir/repo"
rm -rf log logs
mkdir log logs
printf 'new\n' > logs/foo.log
legacy_dir=log
printf 'old\n' > "$legacy_dir/foo.log"
./scripts/migrate_logs.sh >/tmp/migrate.log 2>&1
[[ $(cat logs/foo.log) == new ]]
[[ $(cat logs/foo.log.1) == old ]]
[[ ! -d log ]]
echo "migrate_logs_collision_test OK"
