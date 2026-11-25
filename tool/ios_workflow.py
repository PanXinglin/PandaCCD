#!/usr/bin/env python3
"""Repeatable iOS preflight/build/test. Never installs software or signs in."""
import argparse
import base64
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('action', choices=['check', 'core', 'simulator', 'unsigned', 'device', 'test'])
parser.add_argument('--device', help='Flutter device ID for device/test actions')
args = parser.parse_args()
env = os.environ.copy()
flutter = shutil.which('flutter') or str(Path.home()/'.cache/panda-ccd/toolchains/flutter/bin/flutter')

def run(command):
    subprocess.run(command, cwd=ROOT, env=env, check=True)

if args.action == 'core':
    # Real AVFoundation/Vision helpers on macOS, not an iOS app/device test.
    with tempfile.TemporaryDirectory(prefix='panda-ios-core-') as folder:
        work = Path(folder)
        fixtures = (ROOT/'integration_test/fixtures/media_assets.dart').read_text()
        for variable, filename in [('qaPortrait', 'portrait.jpg'), ('qaAudio', 'audio.mp4')]:
            encoded = re.search(r"const " + variable + r" = '([^']+)';", fixtures)[1]
            (work/filename).write_bytes(base64.b64decode(encoded))
        helpers = ROOT/'packages/panda_media/ios/panda_media/Sources/panda_media'
        files = ['PandaPixels','PandaMovieWriter','PandaAudio','PandaLivePair','PandaFaces','PandaPhotos']
        run(['swiftc','-parse-as-library','tool/ios_core_check.swift',
             *[str(helpers/(name+'.swift')) for name in files],'-o',str(work/'check')])
        run([str(work/'check'),folder])
    sys.exit(0)

developer = Path(env.get('DEVELOPER_DIR','/Applications/Xcode.app/Contents/Developer'))
if not (developer/'usr/bin/xcodebuild').is_file():
    print('BLOCKED: 完整 Xcode 尚未安装；Command Line Tools 无法编译 iOS。')
    sys.exit(2)
env['DEVELOPER_DIR'] = str(developer)
# Dart native build hooks keep PATH but filter out DEVELOPER_DIR. Keep SDK
# discovery on the same Xcode for those subprocesses without switching the Mac.
sdk_tools = tempfile.TemporaryDirectory(prefix='panda-ios-tools-')
xcrun = Path(sdk_tools.name)/'xcrun'
xcrun.write_text(f'#!/bin/sh\nexport DEVELOPER_DIR={shlex.quote(str(developer))}\nexec /usr/bin/xcrun "$@"\n')
xcrun.chmod(0o700)
env['PATH'] = sdk_tools.name + os.pathsep + env.get('PATH', os.defpath)
run(['xcodebuild','-version'])
run(['xcodebuild','-checkFirstLaunchStatus'])
run(['xcrun','--sdk','iphoneos','--show-sdk-version'])
run(['xcrun','--sdk','iphonesimulator','--show-sdk-version'])
if args.action == 'check':
    run([flutter,'devices'])
elif args.action == 'simulator':
    run([flutter,'pub','get'])
    run([flutter,'build','ios','--simulator','--debug','--no-pub','--target','lib/main.dart'])
elif args.action == 'unsigned':
    run([flutter,'pub','get'])
    run([flutter,'build','ios','--release','--no-codesign','--no-pub','--target','lib/main.dart'])
elif args.action == 'device':
    if not args.device: parser.error('--device is required; select a connected trusted iPhone')
    # Release can be launched from the Home Screen without a Flutter debugger.
    run([flutter,'run','--release','--no-resident','-d',args.device,'--target','lib/main.dart'])
else:
    if not args.device: parser.error('--device is required')
    run([flutter,'test','integration_test/ios_pipeline_test.dart','-d',args.device])
