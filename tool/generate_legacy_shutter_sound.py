"""Generate an original short mechanical double-click; no sampled audio."""
import math, random, struct, wave
from pathlib import Path
randomizer = random.Random(20261027)
rate = 44100
frames = []
previous = 0.0
for index in range(int(rate * .115)):
    t = index / rate
    noise = randomizer.uniform(-1, 1)
    transient = noise - previous * .7
    previous = noise
    value = 0.0
    for start, gain in [(0, .65), (.043, .52)]:
        age = t - start
        if age >= 0:
            envelope = min(1, age / .0007) * math.exp(-age / .005)
            value += gain * transient * envelope
            value += gain * .2 * math.sin(2*math.pi*1400*age) * math.exp(-age/.012)
    frames.append(struct.pack('<h', int(max(-.9, min(.9, value)) * 32767)))
output = Path(__file__).resolve().parent.parent / 'tool/legacy-shutter.wav'
with wave.open(str(output), 'wb') as stream:
    stream.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    stream.writeframes(b''.join(frames))
