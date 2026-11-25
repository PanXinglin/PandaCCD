"""Original level-4 HALD PNGs. R changes fastest, then G, then B.
No third-party LUTs or source code are included. Python standard library only.
"""
import math, struct, zlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1] / 'assets/luts'
def png(name, transform):
    side, cube = 64, 16
    raw = bytearray()
    for y in range(side):
        raw.append(0)
        for x in range(side):
            i = y * side + x
            r, g, b = (i % cube / 15, (i // cube) % cube / 15, i // (cube*cube) / 15)
            raw.extend(round(max(0, min(1, v))*255) for v in transform(r,g,b))
    def chunk(kind, data):
        return struct.pack('>I',len(data)) + kind + data + struct.pack('>I',zlib.crc32(kind+data))
    (ROOT / f'{name}.png').write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR',struct.pack('>2I5B',side,side,8,2,0,0,0)) + chunk(b'IDAT',zlib.compress(raw)) + chunk(b'IEND',b''))
ROOT.mkdir(parents=True, exist_ok=True)
png('identity',lambda r,g,b:(r,g,b))
png('jade',lambda r,g,b:(r*.94+.018,g**.96*.99+.01,b**.94*.98+.025))
png('amber',lambda r,g,b:(r**.88*1.07,g**1.04*.96+.015,b**1.12*.86+.025))
png('moon',lambda r,g,b:(r*.91+.035,g*.94+.02,b**.94*1.06+.02))
png('peach',lambda r,g,b:(r**.93*1.03+.015,g**.96*.99+.015,b*.94+.025))
png('pixel',lambda r,g,b:(r**1.08*1.03+.02,g**1.05*.98+.015,b*.96+.03))

# Original model-inspired looks, not extracted manufacturer profiles. HSV shaping
# is applied offline only; preview uses the exact same cross-platform HALD shader.
import colorsys

def look(r,g,b, *, gains=(1,1,1), lift=0, gamma=1, saturation=1, contrast=1,
         cyan_blue=0, red_orange=0, blue_sat=1, green_sat=1):
    h,s,v=colorsys.rgb_to_hsv(r,g,b)
    def hue_weight(center,width):
        distance=min(abs(h-center),1-abs(h-center))
        return max(0,1-distance/width)
    cyan=hue_weight(.5,.14)
    red=hue_weight(0,.12)
    green=hue_weight(.33,.16)
    blue=hue_weight(.62,.16)
    h=(h+cyan*cyan_blue+red*red_orange)%1
    s=max(0,min(1,s*saturation*(1+green*(green_sat-1)+blue*(blue_sat-1))))
    rgb=colorsys.hsv_to_rgb(h,s,v)
    return tuple((((max(0,min(1,c))**gamma-.5)*contrast+.5)*gain+lift)
                 for c,gain in zip(rgb,gains))

png('g12',lambda r,g,b:look(r,g,b,saturation=1.035,contrast=1.015,
    cyan_blue=.012,red_orange=.007,blue_sat=1.015))
png('ixus95',lambda r,g,b:look(r,g,b,gains=(1.025,1.005,.965),
    lift=.008,gamma=.98,saturation=1.025,contrast=.985,red_orange=.004))
png('ixus130',lambda r,g,b:look(r,g,b,gains=(1.012,.988,1.025),
    lift=.008,gamma=.975,saturation=.985,contrast=.99))
png('w350',lambda r,g,b:look(r,g,b,gains=(.975,1.005,1.025),
    saturation=1.055,contrast=1.025,blue_sat=1.035,green_sat=1.015))
png('w830',lambda r,g,b:look(r,g,b,gains=(1.008,1.0,1.008),
    lift=.009,gamma=.965,saturation=.975,contrast=.98))
png('f200exr',lambda r,g,b:look(r,g,b,gains=(.995,1.012,1.008),
    saturation=1.09,contrast=1.045,green_sat=1.07,blue_sat=1.055))
