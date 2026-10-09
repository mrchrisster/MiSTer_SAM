# SPDX-License-Identifier: GPL-3.0-or-later
"""Name-only ZIP directory reader using stdlib ZipFile/ZIP64 end-record logic.

ZipFile normally builds a ZipInfo object for every member, including irrelevant
assets. This read-only subclass streams central-directory names instead; it
cannot extract members. Field/default semantics follow Python 3.9 zipfile.
"""
import struct
import zipfile


class DirectoryZip(zipfile.ZipFile):
    def _RealGetContents(self):
        end = zipfile._EndRecData(self.fp)
        if not end: raise zipfile.BadZipFile('Missing ZIP end record')
        size = end[zipfile._ECD_SIZE]
        offset = end[zipfile._ECD_OFFSET]
        concat = end[zipfile._ECD_LOCATION] - size - offset
        if end[zipfile._ECD_SIGNATURE] == zipfile.stringEndArchive64:
            concat -= zipfile.sizeEndCentDir64 + zipfile.sizeEndCentDir64Locator
        self.start_dir = offset + concat
        if self.start_dir < 0: raise zipfile.BadZipFile('Invalid ZIP directory offset')
        self.directory_size = size
        self.entry_count = end[zipfile._ECD_ENTRIES_TOTAL]

    def names(self):
        self.fp.seek(self.start_dir)
        remaining = self.directory_size
        entries = 0
        while remaining:
            header = self.fp.read(zipfile.sizeCentralDir)
            if len(header) != zipfile.sizeCentralDir:
                raise zipfile.BadZipFile('Truncated central directory')
            fields = struct.unpack(zipfile.structCentralDir, header)
            if fields[zipfile._CD_SIGNATURE] != zipfile.stringCentralDir:
                raise zipfile.BadZipFile('Invalid central directory signature')
            name_length = fields[zipfile._CD_FILENAME_LENGTH]
            other_length = fields[zipfile._CD_EXTRA_FIELD_LENGTH] + fields[zipfile._CD_COMMENT_LENGTH]
            consumed = zipfile.sizeCentralDir + name_length + other_length
            if consumed > remaining: raise zipfile.BadZipFile('Invalid ZIP entry length')
            name = self.fp.read(name_length)
            if len(name) != name_length: raise zipfile.BadZipFile('Truncated ZIP filename')
            self.fp.seek(other_length, 1)
            remaining -= consumed
            entries += 1
            try: name = name.decode('utf-8' if fields[zipfile._CD_FLAG_BITS] & 0x800 else 'cp437')
            except UnicodeDecodeError as error: raise zipfile.BadZipFile('Invalid ZIP filename encoding') from error
            name = name.split('\0', 1)[0]
            if name and not name.endswith('/'): yield name
        if entries != self.entry_count:
            raise zipfile.BadZipFile('ZIP entry count does not match its directory')
