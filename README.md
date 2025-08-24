# DroidHarvester

Bash toolkit to harvest APKs and metadata from an attached Android device via ADB.

## Usage

```bash
./run.sh [--clean-logs]
```

Run with no arguments to open the interactive menu. Pass `--clean-logs` to remove existing log files before starting.

Standalone diagnostic scripts live at `scripts/adb_apk_diag.sh` and `scripts/adb_health.sh`, both of which reuse the core helpers.

## Device selection

DroidHarvester auto-detects a single connected device and normalizes the
serial (stripping spaces and carriage returns). Override detection with
`DEV=<serial>`. If multiple devices are attached, set `DEV` or use the
interactive menu in `run.sh` to choose one.

If ADB reports the device as `unauthorized` or `offline`, run:

```
adb kill-server
adb devices    # accept the RSA prompt on the device
```

## Pull limitations

Retail builds often block direct pulls from `/data/app`. The tools try a
fallback copy to `/data/local/tmp`; if that also fails you'll see a
`Permission denied` message, but the session continues and still produces
a report.
