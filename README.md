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

APK pulls may fail on some retail devices due to filesystem restrictions. DroidHarvester first attempts a direct `adb pull`, then
copies the APK to a readable location on the device and retries. If that also fails, the log will note `pull failed` and the device
likely blocks access. Retail builds often disallow pulling `/data/app` files; use a debug build or accept that extraction is not
possible.

### Troubleshooting

- **Unauthorized / offline** – run `adb kill-server; adb devices` and accept the RSA prompt on the device.
- **Multiple devices** – specify `DEV=<serial>` or select via the menu.
- **Pull failures** – check logs for the copy fallback messages; if both direct and fallback pulls fail, the device is restricting
  access and the APK cannot be harvested.

## Tests

A fake-ADB harness under `tests/fakes/` allows running checks without a device:

```bash
bash -n run.sh lib/**/*.sh scripts/**/*.sh
shellcheck -S warning run.sh lib/**/*.sh scripts/**/*.sh || true
tests/run.sh
```
