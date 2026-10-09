#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Commercial title proposals and preferred ROM copies. No ROM reads/network."""
import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
import hashlib
import os
from pathlib import Path
import random
import re
import sys
import unicodedata
from functools import lru_cache

ROOT = Path(__file__).resolve().parents[1]
TAGS = re.compile(r'\([^)]*\)|\[[^]]*\]')
LABEL = re.compile(r'^(?:\d{4}-\d{2}(?:-\d{2})?\s+|\d{1,3}(?:\.|\s*-)?\s+)')
MODIFIED = re.compile(r'\b(hack|patched|patch|translation|translated|prototype|proto|beta|demo|sample|pirate|aftermarket|unl)\b|\[(?:b|h|o|t)[+0-9-]', re.I)
BAD_PATH = re.compile(r'/(?:[^/]*(?:hacks|translations|prototypes|betas)[^/]*)/',re.I)
EXCLUDED = re.compile(r'VGM|MSU|Disc 2|Sega CD 32X',re.I)
REGIONS = {'usa':0,'u':0,'world':1,'w':1,'europe':2,'e':2,'japan':3,'j':3}
REGION_NAMES = {'us':'usa','u':'usa','w':'world','e':'europe','j':'japan'}


def title(value):
    value=TAGS.sub(' ',value).strip().rstrip('()[] ')
    article=re.match(r'^(.*),\s*(The|An|A)$',value,re.I)
    if article:value=article[2]+' '+article[1]
    return value


@lru_cache(maxsize=32768)
def canonical(value):
    # Unlicensed and Tengen editions cannot become interchangeable with their
    # licensed counterpart merely because parentheses were removed.
    edition='unlicensed' if re.search(r'\((?:unl|unlicensed)\)',value,re.I) else ''
    return ''.join(c for c in unicodedata.normalize('NFKC',title(value)).casefold() if c.isalnum() or c in '+&')+edition


class Catalogue:
    """Optional local indexes supply explicit aliases and familiar dump names."""
    def __init__(self, directories=()):
        self.names=set();self.aliases=defaultdict(set);self.literal=defaultdict(set)
        for directory in directories:
            directory=Path(directory)
            for filename in ['index.tsv','gameinfo.tsv']:
                path=directory/filename
                if not path.is_file():continue
                for line in path.read_text(encoding='utf-8',errors='replace').splitlines():
                    row=line.split('\t')
                    if line.startswith('#'):continue
                    if filename=='index.tsv' and len(row)>=4:
                        name,key=row[0],row[3]
                    elif filename=='gameinfo.tsv' and len(row)>=6:
                        key,name=row[0],row[1]
                    else:continue
                    if not key:continue
                    self.names.update([key.casefold(),name.casefold()])
                    identity=canonical(key)
                    self.literal[name.casefold()].add(identity)
                    self.literal[key.casefold()].add(identity)
                    self.aliases[canonical(name)].add(identity)
                    self.aliases[identity].add(identity)

    def identities(self,value):
        key=canonical(value)
        return self.aliases.get(key,{key})


@dataclass
class Candidate:
    path:str
    stem:str
    name:str
    identities:set
    modified:bool
    catalogued:bool
    labelled:bool
    region:int
    revision:int
    raw_key:str
    title_key:str


def candidate(path,catalogue):
    stem=Path(path.replace('\\','/')).stem
    labelled=bool(LABEL.match(stem)) and stem.casefold() not in catalogue.names
    cleaned=LABEL.sub('',stem,count=1) if labelled else stem
    name=title(cleaned)
    tags=' '.join(TAGS.findall(stem)).casefold()
    regions=[REGIONS[word] for word in re.findall(r'[a-z]+',tags) if word in REGIONS]
    revision=re.search(r'\b(?:rev(?:ision)?\s*|prg\s*)([0-9]+|[a-z])\b',tags)
    revision=int(revision[1]) if revision and revision[1].isdigit() else ord(revision[1])-96 if revision else 0
    identity=catalogue.literal.get(cleaned.casefold(),{canonical(cleaned)})
    return Candidate(path,stem,name,identity,
        bool(MODIFIED.search(stem) or BAD_PATH.search(path)),
        stem.casefold() in catalogue.names,labelled,min(regions,default=4),revision,
        canonical(stem),canonical(name))


def alternatives(query):
    result=[]
    for part in re.split(r'\\?\|',query):
        part=part.strip()
        # Legacy compound metadata contains escaped separators, not arbitrary
        # executable regex. Unsupported escapes cannot become broad matches.
        if '\\' in part:continue
        tag=re.search(r'\(([^()]*)$',part)
        qualifier=tag[1].strip().casefold() if tag else ''
        base=part[:tag.start()].strip() if tag else part
        result.append((base,qualifier))
    return result


def qualifier_matches(item,qualifier):
    if not qualifier:return True
    qualifier=REGION_NAMES.get(qualifier,qualifier)
    tags=' '.join(TAGS.findall(item.stem)).casefold()
    return any(word.startswith(qualifier) for word in re.findall(r'[a-z0-9]+',tags))


def is_sequel(base,wanted):
    # A missing original must not make a sequel a prefix match.
    words=re.findall(r'[a-z0-9]+',title(base).casefold())
    wanted_words=re.findall(r'[a-z0-9]+',title(wanted).casefold())
    if words[:len(wanted_words)]==wanted_words and len(words)>len(wanted_words):
        next_word=words[len(wanted_words)]
        return next_word.isdigit() or next_word in {'ii','iii','iv','v','vi'}
    return False


def matching(items,query,catalogue):
    matches=[];generic=[]
    for base,qualifier in alternatives(query):
        scoped=[item for item in items if qualifier_matches(item,qualifier)]
        if not canonical(base):generic.extend(scoped);continue
        wanted=catalogue.identities(base)
        base_key=canonical(base)
        direct=[item for item in scoped if item.raw_key==base_key or item.title_key==base_key]
        exact=direct or [item for item in scoped if item.identities & wanted]
        if exact:matches.extend(exact);continue
        if base_key in catalogue.aliases:
            # A known indexed game absent from the filtered list is unavailable,
            # not a reason to scan for similarly named authors or other games.
            continue
        # Some published titles are abbreviations. Permit a unique, literal
        # token fragment among retail basenames only; never authors/directories.
        words=re.findall(r'[a-z0-9]+',title(base).casefold())
        partial=[]
        for item in scoped:
            if item.modified or '+' in item.name or is_sequel(item.name,base):continue
            if ' by ' in item.name.casefold() and ' by ' not in base.casefold():continue
            candidate_words=re.findall(r'[a-z0-9]+',item.name.casefold())
            if words and any(candidate_words[i:i+len(words)]==words for i in range(len(candidate_words))):partial.append(item)
        groups={item.title_key for item in partial}
        if len(groups)==1:matches.extend(partial)
    pool=matches if matches else generic
    return list({item.path:item for item in pool}.values()),'matched' if matches else 'generic' if generic else 'no_match'


def preferred(items,rng):
    # Choose a game before comparing revisions: generic commercials must not
    # favour only games with unusually high revision numbers.
    groups=defaultdict(list)
    for item in items:groups[tuple(sorted(item.identities))].append(item)
    has_catalogue_matches=any(item.catalogued for item in items)
    def quality(item):return (item.modified,not item.catalogued if has_catalogue_matches else False,item.labelled)
    best=min(quality(item) for item in items)
    eligible=[name for name,copies in groups.items() if min(quality(item) for item in copies)==best]
    copies=groups[rng.choice(sorted(eligible))]
    def rank(item):return quality(item)+(item.region,-item.revision)
    best=min(rank(item) for item in copies)
    return rng.choice([item for item in copies if rank(item)==best])


def choose(paths,query,catalogue=None,rng=None,fallback=False,items=None):
    catalogue=catalogue or Catalogue();rng=rng or random.SystemRandom()
    if items is None:items=[candidate(path,catalogue) for path in paths if path and not EXCLUDED.search(path)]
    pool,mode=matching(items,query,catalogue)
    if not pool and fallback:pool=items;mode='fallback'
    if not pool:return None,dict(mode='no_match',candidates=0)
    selected=preferred(pool,rng)
    return selected.path,dict(mode=mode,candidates=len(pool),title=selected.name,
        catalogued=selected.catalogued,modified=selected.modified,labelled=selected.labelled)


def catalogue_directories(core):
    sys.path.insert(0,str(ROOT/'artwork'))
    from sam_artwork import SYSTEMS
    folder=SYSTEMS.get(core)
    if not folder:return []
    directories=[ROOT/'artwork/database/docs'/folder/'Artwork']
    directories += [Path(mount)/'docs'/folder/'Artwork' for mount in ['/media/fat']+['/media/usb'+str(i) for i in range(8)]]
    return directories


def prepared(path,directories,cache):
    # Exclusion checks can rewrite an identical session list. Fingerprint its
    # small filename text, not ROM data, so those writes do not rebuild ranking.
    listing=Path(path).read_bytes()
    files=[Path(__file__)]+[Path(d)/f for d in directories for f in ['index.tsv','gameinfo.tsv']]
    stamps=[[str(path),len(listing),hashlib.sha256(listing).hexdigest()]]
    for file in files:
        try:stat=file.stat();stamps.append([str(file),stat.st_size,stat.st_mtime_ns])
        except FileNotFoundError:stamps.append([str(file),None,None])
    if cache:
        try:
            data=json.loads(Path(cache).read_text(encoding='utf-8'))
            if data['format']==2 and data['stamps']==stamps:
                catalogue=Catalogue();catalogue.aliases={k:set(v) for k,v in data['aliases'].items()}
                items=[Candidate(*row[:3],set(row[3]),*row[4:]) for row in data['items']]
                return catalogue,items
        except (OSError,ValueError,KeyError,TypeError,IndexError,AttributeError):pass
    catalogue=Catalogue(directories)
    paths=listing.decode('utf-8',errors='surrogateescape').splitlines()
    items=[candidate(p,catalogue) for p in paths if p and not EXCLUDED.search(p)]
    if cache:
        data=dict(format=2,stamps=stamps,aliases={k:sorted(v) for k,v in catalogue.aliases.items()},
            items=[[x.path,x.stem,x.name,sorted(x.identities),x.modified,x.catalogued,x.labelled,x.region,x.revision,x.raw_key,x.title_key] for x in items])
        destination=Path(cache);temp=destination.with_name(destination.name+'.tmp.'+str(os.getpid()))
        try:
            temp.write_text(json.dumps(data),encoding='utf-8');os.replace(temp,destination)
        finally:temp.unlink(missing_ok=True)
    return catalogue,items


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list',required=True);parser.add_argument('--query-file',required=True)
    parser.add_argument('--core',required=True);parser.add_argument('--fallback',action='store_true')
    parser.add_argument('--result-file');parser.add_argument('--catalogue',action='append')
    parser.add_argument('--cache',help='Session cache; invalidated by list, catalog or helper changes')
    args=parser.parse_args()
    try:
        query=Path(args.query_file).read_text(encoding='utf-8').strip()
        catalogue,items=prepared(args.list,args.catalogue if args.catalogue is not None else catalogue_directories(args.core),args.cache)
        selected,info=choose([],query,catalogue,items=items,fallback=args.fallback)
        if args.result_file:Path(args.result_file).write_text(json.dumps(info),encoding='utf-8')
        if not selected:return 1
        if info['mode']=='fallback':print('SAM commercial: no eligible title match; selecting a preferred game from the filtered list.',file=sys.stderr)
        elif info['mode']=='generic':print('SAM commercial: generic advertisement; selecting a preferred eligible game.',file=sys.stderr)
        print(selected);return 0
    except (OSError,ValueError) as error:
        print('SAM commercial ERROR: '+str(error),file=sys.stderr);return 2


if __name__=='__main__':sys.exit(main())
