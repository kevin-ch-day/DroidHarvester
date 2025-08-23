# DroidHarvester

Bash toolkit to harvest APKs and metadata from an attached Android device via ADB.

## Usage

```bash
./run.sh [--clean-logs]
```

Run with no arguments to open the interactive menu. Pass `--clean-logs` to remove existing log files before starting.

Standalone diagnostic scripts live at `scripts/adb_apk_diag.sh` and `scripts/adb_health.sh`, both of which reuse the core helpers.

## Tests

A fake-ADB harness (`tests/fake_adb.sh`) allows running checks without a device:

```bash
bash -n run.sh lib/**/*.sh scripts/**/*.sh
shellcheck -S warning run.sh lib/**/*.sh scripts/**/*.sh || true
tests/run.sh
```
