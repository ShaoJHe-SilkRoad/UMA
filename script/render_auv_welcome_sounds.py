#!/usr/bin/env python3
"""Renders AUV's first-launch welcome sound and writes it into Swift.

Sound = the first seven tones of the 门楼 melody (1=G, 4/4, quarter = 80;
三弦 line, bar 1: 5̣ 1 6̣ 5̣ 6̣ 1 1̣) as plucked strings.
  - English: the seven tones only.
  - Chinese: a drumbeat, the seven tones, then a greeting the user recorded
    (--zh-voice FILE, m4a/wav/...). Without --zh-voice the Chinese sound is the
    drum and the tones alone.
The recording has its leading and trailing silence trimmed, is made mono at
the same sample rate and is loudness-matched to the tones.

Run:  python3 script/render_auv_welcome_sounds.py [--zh-voice FILE]
Output: Sources/CodexUsageUI/Services/AUVWelcomeSoundData.swift
Needs macOS `afconvert` and ffmpeg (only to prepare the recording).
"""
import argparse, base64, math, random, struct, subprocess, sys, tempfile, wave
from pathlib import Path

SR = 44100
BEAT = 60.0 / 80.0
OUT = Path(__file__).resolve().parent.parent / "Sources/CodexUsageUI/Services/AUVWelcomeSoundData.swift"

# (start beat, length in beats, frequency Hz)   1=G: mid 1 = G4
G4, D4, E4, G3 = 392.00, 293.66, 329.63, 196.00
MELODY = [
    (0.00, 1.00, D4),   # 5̣
    (1.00, 0.75, G4),   # 1 (dotted)
    (1.75, 0.25, E4),   # 6̣
    (2.00, 0.25, D4),   # 5̣
    (2.25, 0.25, E4),   # 6̣
    (2.50, 0.50, G4),   # 1
    (3.00, 1.50, G3),   # 1̣ (held)
]


def pluck(freq, seconds):
    """Karplus-Strong string: a soft plucked 三弦/zither-like tone."""
    n = int(SR * seconds)
    period = int(SR / freq)
    rnd = random.Random(7)
    buf = [rnd.uniform(-1, 1) for _ in range(period)]
    # soften the excitation so it is warm, not buzzy
    for _ in range(2):
        buf = [(buf[i] + buf[i - 1]) / 2 for i in range(period)]
    out = []
    for i in range(n):
        j = i % period
        nxt = (buf[j] + buf[(j + 1) % period]) / 2 * 0.9965
        buf[j] = nxt
        out.append(nxt)
    fade = int(SR * 0.05)
    for i in range(min(fade, n)):
        out[n - 1 - i] *= i / fade
    return out


def drum(seconds=0.9):
    """A low skin-drum hit: pitch-dropping sine plus a short click."""
    out, phase = [], 0.0
    rnd = random.Random(3)
    for i in range(int(SR * seconds)):
        t = i / SR
        f = 55 + 95 * math.exp(-t * 18)
        phase += 2 * math.pi * f / SR
        s = math.sin(phase) * math.exp(-t * 5.5)
        s += (rnd.uniform(-1, 1)) * math.exp(-t * 90) * 0.5
        out.append(s * 0.95)
    return out


def add(mix, start_s, samples, gain):
    start = int(start_s * SR)
    need = start + len(samples)
    if len(mix) < need:
        mix.extend([0.0] * (need - len(mix)))
    for i, v in enumerate(samples):
        mix[start + i] += v * gain


# Drumbeat in front of the tones, per language.
DRUM = {"zh": False, "en": False}
# Loudness target (LUFS) for the recording, chosen to sit with the tones.
VOICE_LUFS = -18
VOICE_TRUE_PEAK = -1.5


def prepare_voice(path, workdir):
    """Trim silence at both ends, level to VOICE_LUFS, mono, SR Hz; returns samples."""
    out = workdir / "zh-voice.wav"
    trim = "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05"
    chain = ",".join([trim, "areverse", trim, "areverse",
                      f"loudnorm=I={VOICE_LUFS}:TP={VOICE_TRUE_PEAK}:LRA=7"])
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(path), "-af", chain,
                    "-ac", "1", "-ar", str(SR), "-sample_fmt", "s16", str(out)], check=True)
    with wave.open(str(out)) as w:
        raw = w.readframes(w.getnframes())
    samples = [x / 32768 for x in struct.unpack("<%dh" % (len(raw) // 2), raw)]
    if len(samples) < SR // 4:
        sys.exit(f"{path}: nothing left after trimming silence")
    return samples


def render(name, workdir, voice_samples=None):
    mix = []
    t0 = 0.0
    if DRUM[name]:
        add(mix, 0.0, drum(), 0.9)
        t0 = 0.55
    for beat, length, freq in MELODY:
        add(mix, t0 + beat * BEAT, pluck(freq, length * BEAT + 0.9), 0.55)
    if voice_samples:
        # Normalising the whole mix below would move the recording's level, so
        # it is scaled against the tones' own peak instead.
        add(mix, t0 + 4.5 * BEAT + 0.25, voice_samples, 0.95)
    peak = max(abs(x) for x in mix) or 1
    pcm = struct.pack("<%dh" % len(mix), *[int(max(-1, min(1, x / peak * 0.89)) * 32767) for x in mix])
    wav_path = workdir / f"welcome-{name}.wav"
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm)
    m4a = workdir / f"welcome-{name}.m4a"
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", str(wav_path), str(m4a)], check=True)
    return m4a.read_bytes(), len(mix) / SR


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("Run:")[0])
    parser.add_argument("--zh-voice", type=Path, help="the user's recorded Chinese greeting")
    args = parser.parse_args()
    if args.zh_voice and not args.zh_voice.is_file():
        sys.exit(f"no such file: {args.zh_voice}")
    with tempfile.TemporaryDirectory() as d:
        work = Path(d)
        zh_voice = prepare_voice(args.zh_voice, work) if args.zh_voice else None
        lines = ["// Generated by script/render_auv_welcome_sounds.py. Do not edit.",
                 "import Foundation", "",
                 "enum AUVWelcomeSoundData {"]
        for name in ("zh", "en"):
            data, secs = render(name, work, zh_voice if name == "zh" else None)
            print(f"{name}: {secs:.1f}s, {len(data)//1024} KB", file=sys.stderr)
            b64 = base64.b64encode(data).decode()
            lines.append(f"    static let {name}: Data = Data(base64Encoded: \"{b64}\")!")
        lines.append("}")
        OUT.write_text("\n".join(lines) + "\n")
    print("wrote", OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
