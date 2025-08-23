# DroidHarvester

DroidHarvester provides an interactive shell for analysts to collect APKs from a connected Android device, extract metadata, and generate reports.

## Prerequisites

- Fedora Linux terminal
- Android Debug Bridge (`adb`) with a device connected
- Command‑line utilities: `jq`, `zip`, `column`
- Hash tools: `sha256sum`, `sha1sum`, `md5sum`

## Usage

```bash
./run.sh                   # launch the menu-driven interface
./run.sh --device <ID>      # preselect device
./run.sh --debug            # enable verbose logging and xtrace file
./run.sh -h|--help          # show options
```

Reports live under `results/` and logs under the repository root `logs/` directory.

Each interactive session writes a transcript to `logs/harvest_log_<timestamp>.txt`.

Each pulled APK is stored under `results/<device>/<package>/<apk>/` alongside
three sidecar reports:

- `<apk>.txt` – human-readable summary with hashes, size, and pull time
- `<apk>.csv` – single-row CSV with the same fields
- `<apk>.json` – machine-readable metadata

### Quick diagnostics

When triaging a failing harvest run these probes:

```bash
adb get-state
adb -s "$DEVICE" shell echo OK
adb -s "$DEVICE" shell pm path com.example.app | wc -l
```

Enable command tracing to file:

```bash
ts=$(date +%Y%m%d_%H%M%S)
LOG_LEVEL=DEBUG ./run.sh --debug 9>"logs/trace_$ts.log"
```

## Utilities

Diagnostics and maintenance scripts live under `scripts/` and are run from that directory:

```bash
cd scripts
./diag_adb_health.sh --debug
./test_get_apk_paths.sh --pkg <package> --debug
./github-helper.sh --debug
./make_executable.sh --debug
```

Each utility writes a timestamped transcript to the repository’s `logs/` folder.

### Fedora packages

Install common dependencies on Fedora:

```bash
sudo dnf install -y android-tools jq zip
# optional helpers
sudo dnf install -y shellcheck
```

## Targeted test recipes

1. Happy path: choose device → scan → harvest one package.
2. Device unplug during harvest: unplug USB for ~10s and replug; confirm retries.
3. Timeout test: `DH_PULL_TIMEOUT=5 ./run.sh --debug` and harvest to trigger `E_TIMEOUT`.


### Environment overrides

- `DH_PULL_TIMEOUT` (default 120)
- `DH_SHELL_TIMEOUT` (default 20)
- `DH_RETRIES` (default 3)
- `DH_BACKOFF` (default 1.5)
