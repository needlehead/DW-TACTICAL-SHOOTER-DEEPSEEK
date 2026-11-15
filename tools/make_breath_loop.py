"""Cut a seamless breathing loop out of a long breath recording.

Picks the quietest moment (between breaths) near START and near START + LENGTH, then crossfades the clip's tail
into its head so the loop point has no click or jump in loudness. Needs ffmpeg on PATH and numpy.

    python tools/make_breath_loop.py "my sounds/generic/<breath>.mp3" "my sounds/generic/breath_loop.ogg"
"""
import subprocess
import sys

import numpy as np

SR, START, LENGTH, SEARCH, FADE = 48000, 10.0, 30.0, 1.5, 0.3


def quietest(env: np.ndarray, around: float, hop: float) -> int:
    lo, hi = int((around - SEARCH) / hop), int((around + SEARCH) / hop)
    return (lo + int(np.argmin(env[lo:hi]))) * int(hop * SR)


def main(src: str, out: str) -> None:
    pcm = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", src, "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(pcm, dtype=np.float32).reshape(-1, 2)
    hop = 0.02
    n = int(hop * SR)
    env = np.sqrt((x[: len(x) // n * n].reshape(-1, n, 2) ** 2).mean(axis=(1, 2)))
    a = quietest(env, START, hop)
    b = quietest(env, START + LENGTH, hop)
    f = int(FADE * SR)
    loop = x[a:b].copy()
    tail = x[b:b + f]  # what follows the end point, faded over the loop's head
    ramp = np.linspace(0.0, 1.0, f, dtype=np.float32)[:, None]
    loop[:f] = loop[:f] * ramp + tail * (1.0 - ramp)
    assert len(loop) > SR * 5, "loop too short"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", out], input=loop.tobytes(), check=True)
    print(f"{out}: {a / SR:.2f}s - {b / SR:.2f}s ({len(loop) / SR:.2f}s loop)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
