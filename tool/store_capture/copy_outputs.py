"""Copy generated artwork from this task's simulator staging directory only."""
from pathlib import Path
import re
import shutil
import time
root = Path(__file__).resolve().parents[2]
log = Path('/tmp/panda-store-capture.log')
out = root / 'app-store/2026-11-12/screenshots/raw'
out.mkdir(parents=True, exist_ok=True)
for _ in range(600):
    text = log.read_text(errors='replace') if log.exists() else ''
    match = re.search(r'STORE_CAPTURE_READY (.+)', text)
    if match:
        source = Path(match[1].strip())
        files = list(source.glob('*.png'))
        for file in files:
            shutil.copy2(file, out/file.name)
        (source/'copied').touch()
        print(f'Copied {len(files)} rendered app screens to {out}', flush=True)
        break
    if 'Some tests failed' in text or 'Failed to build' in text:
        raise RuntimeError('Screenshot renderer failed; inspect log')
    time.sleep(1)
else:
    raise TimeoutError('Screenshot renderer did not publish outputs')
