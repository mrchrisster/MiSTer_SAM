"""Pinned Zaparoo catalog lookup shared by SAM indexing and MGL generation.

SPDX-License-Identifier: GPL-3.0-or-later
Catalog/lookup semantics: ZaparooProject/zaparoo-core (see source record).
No Zaparoo service or non-standard Python packages are required.
"""
import copy
import fnmatch
import hashlib
import json
import os
import posixpath
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent


class CatalogError(ValueError):
    pass


class DirectLaunch(CatalogError):
    pass


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def validate_core(core, expected=None):
    if not isinstance(core, dict) or not isinstance(core.get('id'), str) or not core['id']:
        raise CatalogError('Core requires an ID')
    if expected and core['id'] != expected:
        raise CatalogError('System key/ID mismatch: ' + expected)
    for key in ('rbf', 'setName', 'launcherId'):
        if key in core and not isinstance(core[key], str):
            raise CatalogError('Invalid ' + key + ' for ' + core['id'])
    if 'setNameSameDir' in core and type(core['setNameSameDir']) is not bool:
        raise CatalogError('setNameSameDir must be boolean')
    for key in ('folders', 'extensions', 'rbfAliases'):
        values = core.get(key, [])
        if not isinstance(values, list) or any(not isinstance(x, str) or not x for x in values):
            raise CatalogError('Invalid ' + key + ' for ' + core['id'])
    slots = core.get('slots', [])
    if not isinstance(slots, list): raise CatalogError('slots must be a list')
    for slot in slots:
        if not isinstance(slot, dict): raise CatalogError('Invalid slot')
        if 'label' in slot and not isinstance(slot['label'], str): raise CatalogError('Invalid slot label')
        exts = slot.get('extensions', [])
        if not isinstance(exts, list) or any(not isinstance(x, str) or not x.startswith('.') for x in exts):
            raise CatalogError('Invalid slot extensions')
        params = slot.get('mgl')
        if params is not None:
            if not isinstance(params, dict) or params.get('method') not in ('f', 's'):
                raise CatalogError('Invalid MGL method')
            for key in ('delay', 'index', 'resetDelay', 'resetHold'):
                if key in params and (type(params[key]) is not int or params[key] < 0):
                    raise CatalogError('Invalid MGL numeric field: ' + key)


class Catalog:
    def __init__(self, path=None, compat=None, source=None):
        path = Path(path or ROOT / 'zaparoo_catalog.json')
        self.compat = read_json(compat or ROOT / 'sam_compat.json')
        if not isinstance(self.compat, dict) or self.compat.get('format') != 1 or not isinstance(self.compat.get('aliases'), dict):
            raise CatalogError('Unsupported compatibility policy')
        raw = path.read_bytes()
        self.digest = hashlib.sha256(raw).hexdigest()
        if source is not False:
            record = read_json(source or ROOT / 'zaparoo_catalog_source.json')
            if not isinstance(record, dict) or record.get('sha256') != self.digest:
                raise CatalogError('Pinned catalog checksum mismatch')
        data = json.loads(raw)
        if not isinstance(data, dict): raise CatalogError('Catalog must be an object')
        self.systems, self.groups = data.get('systems'), data.get('groups', {})
        if not isinstance(self.systems, dict) or not self.systems or not isinstance(self.groups, dict):
            raise CatalogError('Catalog requires systems and groups')
        for key, core in self.systems.items(): validate_core(core, key)
        for key, members in self.groups.items():
            if not isinstance(key, str) or not isinstance(members, list) or not members:
                raise CatalogError('Invalid group')
            for member in members:
                validate_core(member)
                if member['id'] not in self.systems: raise CatalogError('Unknown group member: ' + member['id'])
        self.ids = {key.lower(): key for key in self.systems}
        for alias, key in self.compat['aliases'].items():
            if not re.fullmatch(r'[a-z0-9_]+', alias) or (key is not None and key not in self.systems):
                raise CatalogError('Invalid SAM alias: ' + alias)
        for field in ('extensions', 'launch_groups', 'handlers', 'media_slot_aliases'):
            if not isinstance(self.compat.get(field, {}), dict): raise CatalogError('Invalid SAM policy: ' + field)
            for alias in self.compat.get(field, {}):
                if alias not in self.compat['aliases']: raise CatalogError('Unknown policy alias: ' + alias)
        for alias, extensions in self.compat.get('extensions', {}).items():
            if not isinstance(extensions, list) or not extensions or any(not isinstance(x, str) or not re.fullmatch(r'\.[a-zA-Z0-9]+', x) for x in extensions):
                raise CatalogError('Invalid SAM extensions: ' + alias)
        for key in self.compat.get('launch_groups', {}).values():
            if not isinstance(key, str) or key not in self.groups: raise CatalogError('Unknown launch group: ' + str(key))
        for alias, mappings in self.compat.get('media_slot_aliases', {}).items():
            if not isinstance(mappings, dict): raise CatalogError('Invalid media slot aliases')
            for original, target in mappings.items():
                if original not in self.extensions(alias) or not isinstance(target, str) or not target.startswith('.'):
                    raise CatalogError('Invalid media slot alias for ' + alias)
                self.slot(self.launch_core(alias), '/validation' + target)
        roots = self.compat.get('storage_roots')
        if not isinstance(roots, list) or not roots or any(not isinstance(x, str) or not posixpath.isabs(x) for x in roots):
            raise CatalogError('Invalid SAM storage roots')

    def group(self, name):
        """GetGroup: ordered merged slots, retaining the first member's fields."""
        members = copy.deepcopy(self.groups[name])
        for member in members:
            system = self.systems.get(member['id'])
            if system:
                member['folders'] = system.get('folders', [])
                member['extensions'] = system.get('extensions', [])
        merged = members[0]
        merged['slots'] = [slot for member in members for slot in member.get('slots', [])]
        return merged

    def lookup(self, identifier):
        """Upstream Lookup: exact group, then case-insensitive system ID."""
        if identifier in self.groups: return self.group(identifier)
        key = self.ids.get(identifier.lower())
        if key is None: raise CatalogError('Unknown system: ' + identifier)
        return copy.deepcopy(self.systems[key])

    def sam_system(self, identifier):
        """SAM boundaries use explicit systems, avoiding a group's mixed media."""
        alias = identifier.lower()
        key = self.compat['aliases'].get(alias, self.ids.get(alias))
        if key is None: raise CatalogError('System requires a special handler: ' + identifier)
        return self.systems[key]

    def sam_id(self, identifier):
        lower = identifier.lower()
        if lower in self.compat['aliases']: return lower
        core = self.sam_system(identifier)
        for alias, key in self.compat['aliases'].items():
            if key == core['id'] and alias != 'stv': return alias
        return core['id'].lower()

    def extensions(self, identifier):
        alias = self.sam_id(identifier)
        core = self.sam_system(identifier)
        # These restrictions are deliberate SAM policy, not duplicated MGL data.
        allowed = self.compat.get('extensions', {}).get(alias, core.get('extensions', []))
        return tuple(x.lower() for x in allowed)

    def launch_core(self, identifier):
        group = self.compat.get('launch_groups', {}).get(identifier.lower())
        return self.group(group) if group else self.sam_system(identifier)

    def slot(self, core, path):
        lower = path.lower()
        for slot in core.get('slots', []):
            if any(lower.endswith(ext.lower()) for ext in slot.get('extensions', [])):
                if slot.get('mgl') is None: raise DirectLaunch(path)
                # Go int zero values apply to omitted fields; zero is valid.
                params = dict(delay=0, index=0, resetDelay=0, resetHold=0)
                params.update(slot['mgl'])
                return params
        raise CatalogError('No matching media slot for %s: %s' % (core['id'], path))

    def launch_slot(self, identifier, media):
        # Preserve an established SAM media method until a changed upstream
        # slot can be tested on hardware. Values reference catalog slots rather
        # than duplicating their numeric launch parameters.
        alias = self.sam_id(identifier)
        extension = os.path.splitext(media)[1].lower()
        target = self.compat.get('media_slot_aliases', {}).get(alias, {}).get(extension)
        return self.slot(self.launch_core(identifier), '/slot' + target if target else media)

    def rbf_path(self, core, sd='/media/fat', folder=None):
        preferred = core.get('rbf', '')
        if not preferred: raise CatalogError('No RBF for ' + core['id'])
        if folder is not None: preferred = folder.rstrip('/') + '/' + preferred.rsplit('/', 1)[-1]
        directory, base = os.path.split(preferred)
        native_dir = directory if os.path.isabs(directory) else os.path.join(sd, directory)
        canonical = re.compile(re.escape(base) + r'(?:_\d{8})?\.rbf$', re.IGNORECASE)
        def matches(patterns):
            try:
                with os.scandir(native_dir) as entries:
                    names = sorted(entry.name for entry in entries
                                   if entry.name.lower().endswith('.rbf') and entry.is_file())
            except FileNotFoundError: return []
            return [name for name in names if (canonical.fullmatch(name) if patterns is None
                    else any(fnmatch.fnmatchcase(name.lower(), p.lower()) for p in patterns))]
        found = matches(None)
        if not found: found = matches([os.path.basename(p) for p in core.get('rbfAliases', [])])
        if found:
            stem = os.path.splitext(found[-1])[0]
            stem = re.sub(r'_\d{8}$', '', stem)
            return directory.rstrip('/') + '/' + stem
        # MiSTer resolves a canonical undated RBF name itself.
        return preferred
