#!/usr/bin/env python3
"""Summarize system display frame endpoints exported by Animation Hitches.

Frame lifetime is pipeline latency, not a refresh interval. Use consecutive
endpoints instead, select a known continuously moving window, and corroborate
foreground app attribution separately. This is not an app-specific FPS counter.
"""
import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('export', type=Path)
parser.add_argument('--start', type=float, required=True, help='Trace-relative seconds')
parser.add_argument('--end', type=float, required=True, help='Trace-relative seconds')
args = parser.parse_args()
if args.end <= args.start:
    parser.error('--end must exceed --start')
root = ET.parse(args.export).getroot()
ids = {e.attrib['id']: e for e in root.iter() if 'id' in e.attrib}
def value(element):
    return (ids[element.attrib['ref']] if 'ref' in element.attrib else element).text

displays = {}
for node in root.findall('node'):
    schema = node.find('schema')
    if schema is None or schema.attrib.get('name') != 'hitches-frame-lifetimes':
        continue
    for row in node.findall('row'):
        columns = list(row)
        endpoint = (int(value(columns[0])) + int(value(columns[1]))) / 1e9
        if args.start <= endpoint <= args.end:
            displays.setdefault(value(columns[2]), set()).add(endpoint)
output = []
for display, endpoints in sorted(displays.items()):
    ordered = sorted(endpoints)
    intervals = sorted((b - a) * 1000 for a, b in zip(ordered, ordered[1:]))
    if not intervals:
        continue
    def percentile(fraction):
        return intervals[round((len(intervals) - 1) * fraction)]
    output.append({
        'display': display,
        'endpointCount': len(ordered),
        'coveredSeconds': ordered[-1] - ordered[0],
        'endpointHz': len(intervals) / (ordered[-1] - ordered[0]),
        'intervalMs': {'p50': percentile(.5), 'p95': percentile(.95),
                       'p99': percentile(.99), 'maximum': max(intervals)},
        'intervalsAbove12_5ms': sum(i > 12.5 for i in intervals),
        'intervalsAbove25ms': sum(i > 25 for i in intervals),
    })
print(json.dumps({'measurement': 'System display frame lifetime endpoints; verify app and moving-window attribution',
                  'windowSeconds': [args.start, args.end], 'displays': output}, indent=2))
