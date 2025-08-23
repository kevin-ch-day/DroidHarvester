# DroidHarvester

DroidHarvester provides an interactive shell for analysts to collect APKs from a connected Android device, extract metadata, and generate reports.

## Prerequisites

- Fedora Linux terminal
- Android Debug Bridge (`adb`) with a device connected
- Command‑line utilities: `jq`, `zip`, `column`
- Hash tools: `sha256sum`, `sha1sum`, `md5sum`

## Usage

```bash
./run.sh           # launch the menu-driven interface
./run.sh --debug   # enable verbose logging and xtrace file
```

Reports live under `results/` and logs under `logs/`.

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

## Targeted test recipes

1. Happy path: choose device → scan → harvest one package.
2. Device unplug during harvest: unplug USB for ~10s and replug; confirm retries.
3. Timeout test: `DH_PULL_TIMEOUT=5 ./run.sh --debug` and harvest to trigger `E_TIMEOUT`.


### Environment overrides

- `DH_PULL_TIMEOUT` (default 120)
- `DH_SHELL_TIMEOUT` (default 20)
- `DH_RETRIES` (default 3)
- `DH_BACKOFF` (default 1.5)
