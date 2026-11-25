"""Physical-grip emulator driver for stable_camera_test.dart (disposable AVD only)."""
import subprocess,sys,time
from pathlib import Path
adb, logfile=sys.argv[1:]
def run(*args): return subprocess.run([adb,*args],check=True,capture_output=True,text=True)
def wait(marker,timeout=240):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        text=Path(logfile).read_text() if Path(logfile).exists() else ''
        if marker in text:return
        if 'Some tests failed' in text or 'BUILD FAILED' in text:raise SystemExit(text[-2400:])
        time.sleep(.2)
    raise SystemExit('Missing '+marker)
run('emu','sensor','set','acceleration','0:9.81:0')
run('shell','settings','put','system','user_rotation','0')
wait('STABLE_PERMISSION_READY')
run('shell','pm','grant','com.pandaccd.panda_ccd','android.permission.CAMERA')
for name,gravity in [('landscapeLeft','9.81:0:0'),('landscapeRight','-9.81:0:0'),('portraitUp','0:9.81:0')]:
    wait('STABLE_GRIP_'+name)
    run('emu','sensor','set','acceleration',gravity)
    print('Grip '+name,flush=True)
wait('All tests passed!',90)
