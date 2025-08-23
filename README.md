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

## Diagnostics

Run from the `scripts` directory:

```bash
cd scripts
./diag.sh health
./diag.sh paths --pkg com.zhiliaoapp.musically
./diag.sh pull  --pkg com.zhiliaoapp.musically --limit 3
./diag.sh peek
./diag.sh all   --limit 3
```

Logs land under `logs/`.

## Developer checks

```bash
cd scripts
./dev_static_check.sh
./dev_wrapper_selftest.sh
```

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

- `DH_PULL_TIMEOUT` (default 60)
- `DH_SHELL_TIMEOUT` (default 15)
- `DH_RETRIES` (default 3)
- `DH_BACKOFF` (default 1)
