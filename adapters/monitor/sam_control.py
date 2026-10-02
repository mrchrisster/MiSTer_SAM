# SPDX-License-Identifier: AGPL-3.0-or-later
"""Monitor HTTP adapter for SAM's shared command-file transport.

HTTP routes/sequence validation/network policy remain owned by Monitor. The
legacy fallback preserves status-only behavior if modular SAM is uninstalled.
"""
import importlib.util
import os
from pathlib import Path
import sys

_here=Path(__file__).resolve().parent
_shared=Path('/media/fat/Scripts/.MiSTer_SAM/control/sam_control.py')
os.environ.setdefault('SAM_CONTROL_NETWORKS', str(_here/'sam_control_networks.json'))
_path=_shared if _shared.is_file() else _here/'sam_control_legacy.py'
_spec=importlib.util.spec_from_file_location('sam_shared_control', _path)
_module=importlib.util.module_from_spec(_spec)
sys.modules[_spec.name]=_module
_spec.loader.exec_module(_module)
for _name in dir(_module):
    if not _name.startswith('_'):globals()[_name]=getattr(_module,_name)
