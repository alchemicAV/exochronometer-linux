"""Measure dropouts in a recording of the sound device's output.

The point of measuring the DEVICE output rather than the engine's internals: a
counter that says "12.3 s generated in 12.3 s of wall clock" cannot see that the
audio arrives in bursts with silence between them. Bit-exact zero runs can - the
synthesised signal is never exactly zero, so silence in the capture means the
stack delivered silence, not that the instrument went quiet.
"""

import sys
import wave
import struct
import math
from collections import Counter


def analyse(path, label=""):
    w = wave.open(path, "rb")
    n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
    raw = w.readframes(n)
    w.close()
    if n == 0:
        print(f"{label}: EMPTY recording")
        return
    s = struct.unpack("<%dh" % (len(raw) // 2), raw)
    left = [s[i * ch] / 32768.0 for i in range(n)]

    runs, run = [], 0
    for v in left:
        if v == 0.0:
            run += 1
        elif run:
            runs.append(run)
            run = 0
    if run:
        runs.append(run)
    runs = [r for r in runs if r > 2]
    silence = sum(runs)

    mono = [(s[i * ch] + s[i * ch + 1]) / 2.0 / 32768.0 for i in range(n)]

    print(f"{label}")
    print(f"  {n/rate:.2f} s @ {rate} Hz, {ch} ch")
    if not runs:
        print("  NO zero runs: the stream is continuous")
    else:
        lengths = Counter(round(r / rate * 1000) for r in runs)
        period = (n / len(runs)) / rate * 1000
        print(f"  {len(runs)} silence gaps, ~{period:.0f} ms apart")
        print(f"  gap lengths (ms -> count): {dict(lengths.most_common(5))}")
        print(f"  SILENCE: {silence/rate:.2f} s of {n/rate:.2f} s = {silence/n*100:.0f}%")
    mean = math.sqrt(sum(x * x for x in mono) / len(mono))
    print(f"  overall RMS {mean:.5f}")
    return silence / n if n else 0.0


if __name__ == "__main__":
    for path in sys.argv[1:] or ["/tmp/mon.wav"]:
        analyse(path, path)
        print()