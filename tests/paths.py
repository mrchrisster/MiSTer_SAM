from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'package' if (ROOT / 'package/.MiSTer_SAM').is_dir() else ROOT
MONITOR_SERVER = ROOT / 'adapters/monitor/mister_status_server.py'
