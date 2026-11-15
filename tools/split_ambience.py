"""Split a long ambience mix into shuffleable tracks for the Ambience autoload.

Cuts at the quietest moment in each 4-7 minute window (so cuts land in lulls), fades each piece in and out,
and re-encodes to Ogg Vorbis. Needs ffmpeg on PATH and numpy.

    python tools/split_ambience.py "my sounds/ambience/<mix>.mp3" "my sounds/ambience/tracks"
"""
import os
import subprocess
import sys

import numpy as np

MIN_LEN, MAX_LEN, FADE, SR = 240, 420, 3.0, 4000


def main(src: str, out_dir: str) -> None:
    pcm = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", src, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    d = np.frombuffer(pcm, dtype=np.int16).astype(np.float32)
    n = len(d) // SR  # whole seconds
    db = 20 * np.log10(np.sqrt((d[: n * SR].reshape(n, SR) ** 2).mean(1)) + 1)
    db = np.convolve(db, np.ones(3) / 3, "same")
    cuts = [0]
    while cuts[-1] + MAX_LEN < n - 120:
        lo = cuts[-1] + MIN_LEN
        cuts.append(lo + int(np.argmin(db[lo : cuts[-1] + MAX_LEN])))
    cuts.append(n)
    assert all(b > a for a, b in zip(cuts, cuts[1:])), cuts

    os.makedirs(out_dir, exist_ok=True)
    for i, (a, b) in enumerate(zip(cuts, cuts[1:]), 1):
        dur = b - a
        out = os.path.join(out_dir, f"ambience_{i:02d}.ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(a), "-t", str(dur), "-i", src,
                        "-af", f"afade=t=in:d={FADE},afade=t=out:st={dur - FADE}:d={FADE}",
                        "-c:a", "libvorbis", "-q:a", "1", out], check=True)
        print(out, f"{dur // 60}:{dur % 60:02d}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
