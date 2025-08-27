# Guidelines for DroidHarvester contributors

- Run `tests/run.sh` and ensure it passes before submitting changes.
- For shell scripts, prefer Bash; start with `#!/usr/bin/env bash` and enable `set -euo pipefail`.
- Keep line lengths to 100 characters or fewer.
- Use `shellcheck` to lint any shell scripts touched.
- Use `shfmt -i 2 -w` to format shell scripts.
- Production code lives in `lib/` and `run.sh`; `scripts/` is reserved for ad-hoc utilities.
- Source configuration from `config/config.sh`; do not source from `scripts/` in production code.
- Add tests under `tests/` for new features when practical.
- Consult the README for repository conventions and environment variables.
- Commit messages should be concise and written in the imperative mood.
