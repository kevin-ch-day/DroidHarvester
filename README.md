# DroidHarvester

DroidHarvester provides an interactive shell for analysts to collect APKs from a connected Android device, extract metadata, and generate reports.

## Prerequisites

- Android Debug Bridge (`adb`) with a device connected
- Command‑line utilities: `jq`, `zip`, `column`
- Hash tools: `sha256sum`, `sha1sum`, `md5sum`

## Usage

```bash
./run.sh           # launch the menu-driven interface
./run.sh --debug   # enable verbose logging
```

Environment variables may override defaults (e.g., `LOG_LEVEL=DEBUG ./run.sh`). The full configuration and default target package list live in `config.sh`, and extra packages can be supplied via `custom_packages.txt`.

## Logs and Results

Execution logs are written to `logs/harvest_log_<timestamp>.txt`.

Harvested APK metadata and reports are stored in `results/apks_report_<timestamp>.<ext>` with CSV, JSON, and TXT variants.
