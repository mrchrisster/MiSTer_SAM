"""Exact title keys shared by whitelists and curated category fallbacks.

SPDX-License-Identifier: GPL-3.0-or-later
"""
import re
import unicodedata
from functools import lru_cache

EXTENSIONS={'.nes','.fds','.sfc','.smc','.n64','.z64','.v64','.gba','.gb','.gbc','.gg','.sms',
            '.md','.gen','.bin','.32x','.pce','.chd','.cue','.iso','.neo','.mra','.mgl','.crt',
            '.d64','.prg','.tap','.t64','.adf','.zip','.rom','.a26','.a78','.int','.col','.vec'}


def title_text(value):
    value=value.split('\t',1)[0].strip()
    value=re.sub(r'^(?:Game|Demo):\s*','',value,flags=re.I)
    value=value.rsplit('/',1)[-1]
    stem,dot,extension=value.rpartition('.')
    if dot and '.'+extension.lower() in EXTENSIONS:value=stem
    value=re.sub(r'^\d{4}-\d{2}-\d{2}\s+','',value)
    value=re.sub(r'^\d+[.)]\s+','',value)
    value=re.split(r'\s*[\[(]',value,maxsplit=1)[0].strip().replace('_',' ')
    if re.search(r',\s*(The|A|An)$',value,re.I):
        value=re.sub(r',\s*(The|A|An)$','',value,flags=re.I)
    value=re.sub(r'^(The|A|An)\s+','',value,flags=re.I)
    return value.strip()


def title_key(value):
    return _text_key(title_text(value))


@lru_cache(maxsize=4096)
def _text_key(value):
    # Cache short normalized titles, never complete ROM paths or collection
    # contents. Genre/archive copies and regional releases reuse the same key.
    if any('\ud800' <= character <= '\udfff' for character in value):
        return ''  # Invalid filename bytes cannot disappear into a known alias.
    value=unicodedata.normalize('NFKD',value).casefold()
    return ''.join(c for c in value if c.isalnum() and not unicodedata.combining(c))


def title_keys(value):
    """Exact leaf title, plus immediate title directory for generic CD leaves.

    A title elsewhere in the path never contributes a key. Only standard CD
    image extensions and literal numbered disc/track names permit a parent key.
    """
    keys = {title_key(value)}
    parts = value.split('\t', 1)[0].strip().split('/')
    if len(parts) > 1:
        leaf = parts[-1]
        stem, dot, extension = leaf.rpartition('.')
        if dot and extension.casefold() in {'chd', 'cue', 'bin', 'iso'}:
            generic = title_key(stem)
            if re.fullmatch(r'(?:disc|disk|cd|track)0*\d{1,2}', generic):
                parent = title_key(parts[-2])
                if parent:
                    keys.add(parent)
    keys.discard('')
    return keys


def altered_release(value):
    """A reviewed stock title does not certify content-changing hacks/demos."""
    value=value.split('\t',1)[0]
    folders=value.split('/')[:-1]
    if any(re.search(r'\b(hacks?|prototypes?|betas?|translations?|homebrew|unlicensed|aftermarket|bootlegs?|pirated?)\b',
                     folder,re.I) for folder in folders):return True
    return bool(re.search(r'[\[(][^\])]*(hack|proto|beta|translation|t[+-][a-z]{2}|unl|homebrew|demo|aftermarket|bootleg|pirated?)[^\])]*[\])]',
                          value.rsplit('/',1)[-1],re.I))
