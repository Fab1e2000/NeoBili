#!/usr/bin/env python3
"""Build an isolated, opt-in Release performance demo for a physical iPhone."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import argparse

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
args = parser.parse_args()
dest = root / 'DerivedData/PerformanceDemo'
dest.mkdir(parents=True, exist_ok=True)
project = dest / 'NeoBili.xcodeproj'
shutil.copytree(root / 'NeoBili.xcodeproj', project, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('xcuserdata'))
s = (root / 'NeoBili.xcodeproj/project.pbxproj').read_text()
s = s.replace('PRODUCT_BUNDLE_IDENTIFIER = com.elsterlee.NeoBili;',
              'PRODUCT_BUNDLE_IDENTIFIER = com.elsterlee.NeoBili.performance;')
s = s.replace('PRODUCT_BUNDLE_IDENTIFIER = com.elsterlee.NeoBiliTests;',
              'PRODUCT_BUNDLE_IDENTIFIER = com.elsterlee.NeoBili.performanceTests;')
s = s.replace('INFOPLIST_FILE = NeoBili/Info.plist;', 'INFOPLIST_FILE = PerformanceInfo.plist;')
(project / 'project.pbxproj').write_text(s)
for name in ['NeoBili', 'NeoBiliTests']:
    link = dest / name
    if not link.exists():
        link.symlink_to(root / name, target_is_directory=True)
info = plistlib.loads((root / 'NeoBili/Info.plist').read_bytes())
info['CFBundleDisplayName'] = 'NeoBili 性能 Demo'
info['UIFileSharingEnabled'] = True
info['LSSupportsOpeningDocumentsInPlace'] = True
(dest / 'PerformanceInfo.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['xcodebuild', '-project', str(project), '-scheme', 'NeoBili',
    '-configuration', 'Release', '-destination', f'platform=iOS,id={args.device}',
    '-derivedDataPath', str(dest / 'Build'), '-clonedSourcePackagesDirPath', str(root / 'DerivedData/SourcePackages'),
    '-allowProvisioningUpdates', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=PERFORMANCE_DEMO', 'build'], check=True)
print(dest / 'Build/Build/Products/Release-iphoneos/NeoBili.app')
