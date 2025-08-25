# DroidHarvester

Bash toolkit to harvest APKs and metadata from an attached Android device via ADB.

## Prerequisites

- [Android Debug Bridge (ADB)](https://developer.android.com/studio/command-line/adb)
- A device with USB debugging enabled

## Usage

```bash
./run.sh
```

Run with no arguments to open the interactive menu. Set `CLEAR_LOGS=true` to
remove existing log files before starting.

Typical workflow:

1. Connect a single device and run `./run.sh`.
2. Choose **Scan for target apps** to detect installed packages.
3. Choose **Harvest** to pull APK splits and metadata for discovered apps.

Artifacts and logs are written under `results/<serial>/` and `$LOG_ROOT` (default `logs/`) by default.

After `[4] Quick APK Harvest`, friendly copies are normalized under
`results/<serial>/quick_pull_results/`. Each app gets a human-friendly
directory and versioned filename, and a run-level `manifest.csv` lists
every base and split APK. Package→name mappings live in
`config/packages.sh` and can be customized.

Standalone diagnostic scripts live at `scripts/adb_apk_diag.sh` and
`scripts/adb_health.sh`, both of which reuse the core helpers.

Use `scripts/cleanup_outputs.sh` or the "Clear logs/results" menu option to
remove all previous artifacts and start fresh.

## Diagnostics

```bash
cd scripts
./adb_health.sh
./adb_apk_diag.sh com.zhiliaoapp.musically   # writes results/<DEVICE>/manual_diag_<ts>
```

## Configuration layout & overrides

Configuration defaults live under `config/` and are loaded via `config/config.sh`.
To tweak settings, create `config/local.sh` and assign variables such as
`LOG_LEVEL=DEBUG`. New code should source `config/config.sh`; the repository
root `config.sh` remains as a shim for legacy scripts.

## Using device helper modules

To write scripts that interact with a device:

```bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/config/config.sh"
source "$ROOT/lib/logging/logging_engine.sh"
source "$ROOT/lib/core/device/env.sh"
source "$ROOT/lib/core/device/select.sh"
source "$ROOT/lib/core/device/wrappers.sh"
source "$ROOT/lib/core/device/pm.sh"
```


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

## Device capability report

The interactive menu includes a **Device capability report** option. It prints
build tags (`ro.build.tags`), debug status (`ro.debuggable`), root availability,
and the harvest strategy selected for each target package. Reviewing this output
helps explain why APK pulls may succeed or be skipped on a given device.

## Pull limitations

Retail builds often block direct pulls from `/data/app`. The tools try a
series of fallbacks: copy via `run-as` for debuggable apps, or `su 0 cp`
to `/data/local/tmp` when root is present. If every attempt fails you'll
see a `Permission denied` message, but the session continues and still
produces a report.

## Why APK pulls may fail on retail devices

On stock, non-rooted phones most app code under `/data/app` isn't readable by
the shell user. DroidHarvester probes each package once and picks the first
working strategy:

1. Direct `adb pull` if the file is readable.
2. `run-as <package>` copy for debuggable apps.
3. `su 0` copy when root is available.

If none succeed you'll see a message such as:

```
[ERR] com.whatsapp: APKs not readable on device (no direct read, no run-as, no root)
```

In this case the tool skips APK binaries but still records metadata.

## Debugging & environment knobs

The behaviour of pull helpers can be tuned with environment variables:

| Variable | Effect |
|----------|--------|
| `DEBUG=1` | Print extra device/command traces. |
| `DH_DRY_RUN=1` | Show planned actions without pulling files. |
| `DH_INCLUDE_SPLITS=0` | Pull only base APKs, skip splits. |
| `DH_VERIFY_PULL=0` | Skip SHA256 verification of pulled files. |
| `DH_SHELL_TIMEOUT` | Seconds for adb shell ops (default 15). |
| `DH_PULL_TIMEOUT` | Seconds for adb pull (default 60). |
| `DH_RETRIES` | Retry count for ADB commands (default 3). |
| `DH_BACKOFF` | Seconds between retries (default 1). |

## UI theme configuration

The interactive menus use a high-contrast palette tuned for dark terminals. Use the following knobs to adjust or disable styling:

- `NO_COLOR=1` – disable all colors.
- `DH_THEME=mono` – keep layout but drop colors.
- `DH_THEME=dark-hi` – explicit high-contrast theme (default).
- `DH_NO_UNICODE=1` – use plain ASCII borders instead of Unicode.

## Tests

The repository includes a small integration test suite that uses a fake ADB
shim. Run it with:

```bash
tests/run.sh
```

## Repo Conventions

- All logs are stored under `$LOG_ROOT` (default `./logs/`).
- `scripts/` contains ad-hoc utilities; production code in `lib/` and `run.sh`
  must not source from it.
- `tests/` holds canonical tests and guards.

### Environment variables

- `LOG_ROOT` – base directory for logs (defaults to `./logs`).
- `LOG_KEEP_N` – if set to an integer, retain only that many recent log files.
- `CLEAR_LOGS` – set to `true` to delete existing logs at startup.
