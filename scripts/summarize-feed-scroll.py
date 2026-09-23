#!/usr/bin/env python3
"""Summarize diagnostic callback cadence; does not claim GPU-presented FPS."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('recording', type=Path)
args = parser.parse_args()
samples = json.loads(args.recording.read_text())
if not samples:
    raise SystemExit('No scroll samples')
intervals = sorted(s['callbackInterval'] * 1000 for s in samples)
def percentile(fraction):
    return intervals[round((len(intervals) - 1) * fraction)]
result = {
    'measurement': 'CADisplayLink callback delivery, not presented frames',
    'samples': len(samples),
    'durationSeconds': sum(s['callbackInterval'] for s in samples),
    'callbackHz': len(samples) / sum(s['callbackInterval'] for s in samples),
    'intervalMs': {'p50': percentile(.5), 'p95': percentile(.95), 'p99': percentile(.99), 'maximum': max(intervals)},
    'callbacksAbove12_5ms': sum(i > 12.5 for i in intervals),
    'callbacksAbove25ms': sum(i > 25 for i in intervals),
    'scheduled120HzFraction': sum(s['scheduledInterval'] < .009 for s in samples) / len(samples),
    'itemCountRange': [min(s['itemCount'] for s in samples), max(s['itemCount'] for s in samples)],
    'thermalStates': sorted(set(s['thermalState'] for s in samples)),
    'lowPowerModeObserved': any(s['lowPowerMode'] for s in samples),
}
print(json.dumps(result, ensure_ascii=False, indent=2))
