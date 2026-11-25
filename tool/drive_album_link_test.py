"""Drive the two host-side actions for integration_test/album_link_test.dart.
Usage: python3 tool/drive_album_link_test.py /path/to/adb /path/to/test.log
Run only against a disposable test device: grants image access and deletes the
specific newly generated test asset announced by the test, never other media.
"""
import re
import subprocess
import sys
import time
from xml.etree import ElementTree as E
from pathlib import Path

adb, log_path = sys.argv[1:]
log = Path(log_path)

def wait(pattern, seconds=300):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        content = log.read_text() if log.exists() else ''
        match = re.search(pattern, content)
        if match:
            return match
        if 'Some tests failed' in content or 'BUILD FAILED' in content:
            raise SystemExit(content[-2000:])
        # The plugin correctly uses the OS confirmation even for app exports.
        activity = subprocess.check_output([adb, 'shell', 'dumpsys', 'activity', 'activities'], text=True)
        if re.search(r'topResumedActivity=.*media.*PermissionActivity', activity):
            subprocess.run([adb, 'shell', 'uiautomator', 'dump', '/sdcard/panda-album-test.xml'], stdout=subprocess.DEVNULL)
            xml = subprocess.check_output([adb, 'shell', 'cat', '/sdcard/panda-album-test.xml'], text=True)
            root = E.fromstring(xml)
            titles = [n.get('text', '') for n in root.iter('node') if n.get('resource-id', '').endswith('/dialog_title')]
            if not any('delete' in title.lower() for title in titles):
                raise SystemExit('Unexpected media permission dialog; refusing to approve')
            for node in root.iter('node'):
                if node.get('resource-id') == 'android:id/button1' and node.get('text') == 'Allow':
                    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
                    subprocess.run([adb, 'shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2)], check=True)
                    print('Confirmed generated test media deletion', flush=True)
        time.sleep(.2)
    raise SystemExit(f'Test marker not received: {pattern}')

wait('ALBUM_PERMISSION_READY')
subprocess.run([adb, 'shell', 'pm', 'grant', 'com.pandaccd.panda_ccd',
                'android.permission.READ_MEDIA_IMAGES'], check=True)
print('Granted image access', flush=True)
asset = wait(r'EXTERNAL_DELETE_READY_(\d+)', 60).group(1)
subprocess.run([adb, 'shell', 'input', 'keyevent', '3'], check=True)
subprocess.run([adb, 'shell', 'content', 'delete', '--uri',
                f'content://media/external/images/media/{asset}'], check=True)
print('Deleted only the announced test asset externally', flush=True)

subprocess.run([adb, 'shell', 'am', 'start', '-n', 'com.pandaccd.panda_ccd/.MainActivity'], check=True)
wait(r'All tests passed!', 120)
