#!/usr/bin/env python3
"""Summarize an xctrace time-profile XML export, resolving shared XML references."""
import argparse
from collections import Counter
import json
from pathlib import Path
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('xml', type=Path)
parser.add_argument('--pid', type=int, required=True)
parser.add_argument('--after', type=float, default=0)
parser.add_argument('--before', type=float, default=float('inf'))
args = parser.parse_args()
root = ET.parse(args.xml).getroot()
references = {e.get('id'): e for e in root.iter() if e.get('id')}
def resolve(element):
    return references[element.get('ref')] if element.get('ref') else element

inclusive = Counter()
leaf = Counter()
threads = Counter()
main_samples = 0
main_weight = 0
for row in root.iter('row'):
    columns = list(row)
    if len(columns) != 7:
        continue
    process = resolve(columns[2])
    pid = process.find('pid')
    if pid is None or int(resolve(pid).text) != args.pid:
        continue
    seconds = int(resolve(columns[0]).text) / 1e9
    if not args.after <= seconds <= args.before:
        continue
    weight = int(resolve(columns[5]).text) / 1e6
    thread = resolve(columns[1]).get('fmt', '')
    threads[thread] += weight
    if 'Main Thread' not in thread:
        continue
    main_samples += 1
    main_weight += weight
    frames = [resolve(frame).get('name', '?') for frame in resolve(columns[6]) if frame.tag == 'frame']
    for name in set(frames):
        inclusive[name] += weight
    if frames:
        leaf[frames[0]] += weight

def top(counter):
    return [{'symbol': symbol, 'weightMs': weight, 'mainThreadPercent': round(100 * weight / main_weight, 2)}
            for symbol, weight in counter.most_common(100)] if main_weight else []
print(json.dumps({'pid': args.pid, 'afterSeconds': args.after,
                  'beforeSeconds': args.before if args.before != float('inf') else None,
                  'mainThreadSamples': main_samples, 'mainThreadWeightMs': main_weight,
                  'threadWeightsMs': dict(threads), 'inclusive': top(inclusive), 'leaf': top(leaf),
                  'caveat': 'Statistical CPU samples, not frame durations. Inclusive values overlap; do not sum them.'},
                 ensure_ascii=False, indent=2))
