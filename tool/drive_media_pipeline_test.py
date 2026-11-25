"""Grant emulator test permissions and retain evidence before Flutter uninstalls.

Start alongside flutter test integration_test/media_pipeline_test.dart -d DEVICE.
Redirect that command's output to --log. Use only with a disposable test install.
"""
import argparse
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--adb', default='adb')
parser.add_argument('--device', default='emulator-5554')
parser.add_argument('--log', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
adb = [args.adb, '-s', args.device]
package = 'com.pandaccd.panda_ccd'
deadline = time.monotonic() + 600
granted = copied = False
while time.monotonic() < deadline:
    log = args.log.read_text(errors='replace') if args.log.exists() else ''
    if not granted and 'MEDIA_READY_FOR_PERMISSIONS' in log:
        for permission in ['CAMERA', 'RECORD_AUDIO', 'READ_MEDIA_IMAGES']:
            subprocess.run(adb + ['shell', 'pm', 'grant', package,
                                 'android.permission.' + permission],
                           capture_output=True, check=True)
        granted = True
        print('Test permissions granted', flush=True)
    if not copied and 'MEDIA_ARTIFACT_READY' in log:
        evidence = subprocess.run(
            adb + ['exec-out', 'run-as', package, 'tar', '-C', 'app_flutter',
                   '-cf', '-', 'media-qa'], capture_output=True, check=True)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(evidence.stdout)
        copied = True
        print('Evidence retained', flush=True)
    if 'Some tests failed' in log or 'BUILD FAILED' in log:
        raise SystemExit(log[-4000:])
    if 'All tests passed!' in log:
        if not copied:
            raise SystemExit('Tests passed but evidence was not retained')
        print('Native media integration passed', flush=True)
        break
    time.sleep(.2)
else:
    raise SystemExit('Native media integration timed out')
