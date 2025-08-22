# DroidHarvester

DroidHarvester is an interactive console for collecting APKs from Android devices, extracting metadata, and generating analyst reports.

## Prerequisites

* Android Debug Bridge (`adb`) with a device connected
* `jq`, `zip`, `column`
* `sha256sum`, `sha1sum`, `md5sum`

## Basic Usage

```bash
./run.sh           # launch the menu-driven interface
./run.sh --debug   # enable verbose logging
```

## Logs and Results

Logs are written to the `logs/` directory (e.g., `logs/harvest_log_<timestamp>.txt`).

Harvested APK metadata and reports are stored in `results/` with CSV, JSON, and TXT formats (e.g., `results/apks_report_<timestamp>.<ext>`).
