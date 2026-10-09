#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate a complete MGL from the same pinned catalog used by samindex."""
import argparse
import os
from pathlib import Path
import sys
import tempfile
import xml.etree.ElementTree as ET

from sam_catalog import Catalog, CatalogError, DirectLaunch


def generate(catalog, system, media, sd='/media/fat', folder=None):
    if media.lower().endswith('.mgl'):
        raise DirectLaunch(media)
    core = catalog.launch_core(system)
    params = catalog.launch_slot(system, media)
    document = ET.Element('mistergamedescription')
    ET.SubElement(document, 'rbf').text = catalog.rbf_path(core, sd, folder)
    if core.get('setName'):
        attrs = {'same_dir': '1'} if core.get('setNameSameDir', False) else {}
        ET.SubElement(document, 'setname', attrs).text = core['setName']
    ET.SubElement(document, 'file', {
        'delay': str(params['delay']), 'type': params['method'],
        'index': str(params['index']), 'path': '../../../../..' + media,
    })
    if params['resetDelay'] > 0:
        ET.SubElement(document, 'reset', {'delay': str(params['resetDelay']), 'hold': str(params['resetHold'])})
    return ET.tostring(document, encoding='unicode') + '\n'


def atomic_write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=path.name+'.tmp.', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        try: os.unlink(temp)
        except FileNotFoundError: pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('system')
    parser.add_argument('media')
    parser.add_argument('-o', '--output')
    parser.add_argument('--sd-root', default='/media/fat')
    parser.add_argument('--rbf-folder')
    parser.add_argument('--catalog')
    parser.add_argument('--compat')
    parser.add_argument('--source-record')
    args = parser.parse_args()
    try:
        cat = Catalog(args.catalog, args.compat, args.source_record)
        text = generate(cat, args.system, args.media, args.sd_root, args.rbf_folder)
        if args.output: atomic_write(args.output, text)
        else: sys.stdout.write(text)
        return 0
    except DirectLaunch:
        print('Direct launch: ' + args.media, file=sys.stderr)
        return 3
    except (OSError, CatalogError, ValueError) as error:
        print('SAM MGL: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
