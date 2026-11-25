"""Build the app marks and launcher icons from the original SVG on macOS.

Requires Pillow and macOS sips. Run from any directory.
"""
from pathlib import Path
import json
import re
import subprocess
import tempfile

from PIL import Image

root = Path(__file__).resolve().parents[1]
brand = root / 'assets/brand'
ios = root / 'ios/Runner/Assets.xcassets'
android = root / 'android/app/src/main/res'
mark = (brand / 'panda-mark.svg').read_text().split('>', 1)[1].rsplit('</svg>', 1)[0]

launcher_background = """
<defs>
  <radialGradient id="launcherPearl" cx=".34" cy=".2" r=".95">
    <stop stop-color="#fcfdff"/><stop offset=".6" stop-color="#f2f4f7"/>
    <stop offset="1" stop-color="#e7ebef"/>
  </radialGradient>
</defs>
<rect width="100" height="100" fill="url(#launcherPearl)"/>
"""

with tempfile.TemporaryDirectory(prefix='panda-icon-') as temp:
    temp = Path(temp)

    def render(content, edge=1024):
        svg, png = temp / 'source.svg', temp / 'raster.png'
        svg.write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{edge}" '
            f'height="{edge}" viewBox="0 0 100 100">{content}</svg>'
        )
        subprocess.run(
            ['sips', '-s', 'format', 'png', str(svg), '--out', str(png)],
            check=True, capture_output=True,
        )
        with Image.open(png) as image:
            return image.copy()

    def save(image, size, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        image.resize((size, size), Image.Resampling.LANCZOS).save(path)

    mark_image = render(mark)
    save(mark_image, 256, brand / 'panda-mark.png')
    icon = render(launcher_background + mark).convert('RGB')
    iconset = ios / 'AppIcon.appiconset'
    for slot in json.loads((iconset / 'Contents.json').read_text())['images']:
        if 'filename' in slot:
            edge = round(float(slot['size'].split('x')[0]) * float(slot['scale'].rstrip('x')))
            save(icon, edge, iconset / slot['filename'])

    for density, edge in {
        'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
    }.items():
        save(icon, edge, android / f'mipmap-{density}/ic_launcher.png')

    foreground = render('<g transform="translate(16.5 16.5) scale(.67)">' + mark + '</g>')
    save(foreground, 432, android / 'drawable-nodpi/panda_icon_foreground.png')

    launch = ios / 'LaunchImage.imageset'
    for slot in json.loads((launch / 'Contents.json').read_text())['images']:
        edge = 84 * int(re.sub(r'x$', '', slot['scale']))
        save(mark_image, edge, launch / slot['filename'])
