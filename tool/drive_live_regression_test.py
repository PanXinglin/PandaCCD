"""Drive a disposable AVD for live_regression_test.dart.

Usage: python tool/drive_live_regression_test.py ADB LOG OUTPUT_TAR
Run on physical-density compact and >=600dp AVD profiles separately;
pass --dart-define=PANDA_QA_EXPANDED=true to Flutter for the latter.
"""
import subprocess,time,sys
from pathlib import Path
adb,logfile,output=sys.argv[1:];log=Path(logfile)
def run(*args):return subprocess.run([adb,*args],capture_output=True,check=True)
seen=set();end=time.monotonic()+700
while time.monotonic()<end:
 s=log.read_text(errors='replace') if log.exists() else ''
 if 'LIVE_ROTATION_PERMISSION' in s and 'perm' not in seen:
  run('shell','pm','grant','com.pandaccd.panda_ccd','android.permission.CAMERA');run('shell','pm','grant','com.pandaccd.panda_ccd','android.permission.RECORD_AUDIO');seen.add('perm')
 for line in s.splitlines():
  if not line.startswith('LIVE_ROTATION_READY_'):continue
  key=line.split('READY_')[1]
  if key in seen:continue
  mode,lens,pose=key.split('_')
  run('shell','settings','put','system','accelerometer_rotation','0')
  rotation={'portraitUp':'0','landscapeLeft':'1','portraitDown':'2','landscapeRight':'3'}[pose] if mode=='expanded' else '0'
  run('shell','settings','put','system','user_rotation',rotation)
  gravity={'portraitUp':'0:9.81:0','landscapeLeft':'9.81:0:0','portraitDown':'0:-9.81:0','landscapeRight':'-9.81:0:0'}[pose]
  run('emu','sensor','set','acceleration',gravity);time.sleep(1.2)
  run('shell','run-as','com.pandaccd.panda_ccd','touch','app_flutter/live-regression/'+key+'.ack');seen.add(key);print(key,flush=True)
 if ('LIVE_REGRESSION_ARTIFACT_READY' in s or 'LIVE_FAILURE_ARTIFACT_READY' in s) and 'artifact' not in seen:
  Path(output).write_bytes(run('exec-out','run-as','com.pandaccd.panda_ccd','tar','-C','app_flutter','-cf','-','live-regression').stdout);seen.add('artifact')
 if 'Some tests failed' in s or 'BUILD FAILED' in s:raise SystemExit(s[-3500:])
 if 'All tests passed!' in s:print('PASS',flush=True);break
 time.sleep(.2)
else:raise SystemExit('TIMEOUT')
