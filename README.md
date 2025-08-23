# DroidHarvester

Bash toolkit to harvest APKs and metadata from an attached Android device via ADB.

## Usage

```bash
./run.sh
```

Run with no arguments to open the interactive menu. Supplying any arguments causes the tool to print a short message and exit.

A standalone diagnostic script lives at `scripts/adb_apk_diag.sh` and uses the same helpers.

## Tests

A fake-ADB harness (`tests/fake_adb.sh`) allows running checks without a device:

```bash
bash -n run.sh lib/**/*.sh scripts/**/*.sh
shellcheck -S warning run.sh lib/**/*.sh scripts/**/*.sh || true
tests/run.sh
```
