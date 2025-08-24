# DroidHarvester

Bash toolkit to harvest APKs and metadata from an attached Android device via ADB.

## Usage

```bash
./run.sh [--clean-logs]
```

Run with no arguments to open the interactive menu. Pass `--clean-logs` to remove existing log files before starting.

Standalone diagnostic scripts live at `scripts/adb_apk_diag.sh` and `scripts/adb_health.sh`, both of which reuse the core helpers.

## Device selection

Scripts auto-detect the first attached device and trim any stray whitespace or carriage returns from the serial number. Override detection with `DEV=<serial>`.

If multiple devices are connected, set `DEV` explicitly or use the interactive menu in `run.sh`. When a device shows as `unauthorized` or `offline`, run:

```
adb kill-server
adb devices    # accept the RSA prompt on the device
```

APK pulls may fail on some retail devices due to filesystem restrictions; this is expected and not treated as a bug.

## Tests

A fake-ADB harness under `tests/fakes/` allows running checks without a device:

```bash
bash -n run.sh lib/**/*.sh scripts/**/*.sh
shellcheck -S warning run.sh lib/**/*.sh scripts/**/*.sh || true
tests/run.sh
```
