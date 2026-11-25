"""Force real API 36 large-window rotation (disposable emulator only)."""
import subprocess,sys,time
from pathlib import Path
adb,logfile=sys.argv[1:3]
window_only="--window-only" in sys.argv[3:]
def run(*args):return subprocess.run([adb,*args],capture_output=True,text=True,check=True)
def wait(marker,timeout=240):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        text=Path(logfile).read_text() if Path(logfile).exists() else ''
        if marker in text:return
        if 'Some tests failed' in text or 'BUILD FAILED' in text:raise SystemExit(text[-2500:])
        time.sleep(.15)
    raise SystemExit('Missing '+marker)
run('shell','settings','put','system','accelerometer_rotation','0')
wait('EXPANDED_PERMISSION_READY')
run('shell','pm','grant','com.pandaccd.panda_ccd','android.permission.CAMERA')
previous=None
for name,rotation in [('landscapeLeft','1'),('portraitUp','0'),('landscapeRight','3'),('portraitUp','0')]:
    if previous:wait('EXPANDED_PHOTO_'+previous)
    wait('EXPANDED_ROTATE_'+name)
    run('shell','settings','put','system','user_rotation',rotation)
    time.sleep(.6)  # OS configuration precedes the final physical sensor pose.
    gravity={'landscapeLeft':'9.81:0:0','landscapeRight':'-9.81:0:0','portraitUp':'0:9.81:0'}[name]
    if not window_only:run('emu','sensor','set','acceleration',gravity)
    print('OS rotation '+name,flush=True)
    previous=name
wait('EXPANDED_FOCUS_READY')
run('shell','cmd','statusbar','expand-notifications')
time.sleep(2)
run('shell','cmd','statusbar','collapse')
wait('All tests passed!',90)
