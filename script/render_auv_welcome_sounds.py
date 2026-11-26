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

Two more sounds go with the Wabi-Sabi and Brutalist looks (any language):
  - wabiSabi: the same seven tones moved into the Japanese 都节 (In) scale
    on D (D E♭ G A B♭): 6̣ (E) becomes E♭, so 5̣–6̣ is a half step. Played on
    a koto-like string, slower (quarter = 66), the last note pressed up a
    little after it is struck (後押し), in a small room.
  - brutalist: the first six notes of the Soviet anthem (Alexandrov, 1944;
    "Со-юз не-ру-ши-мый": G | C G. A | B E) low and loud on a raw sawtooth
    brass with a sub octave, a heavy hit on each downbeat, quarter = 126.

Run:  python3 script/render_auv_welcome_sounds.py [--zh-voice FILE] [--preview-dir DIR]
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
    return encode(name, mix, workdir)


def encode(name, mix, workdir, preview_dir=None):
    """Peak-normalises `mix`, writes it as 16-bit mono WAV, returns (AAC m4a bytes, seconds)."""
    peak = max(abs(x) for x in mix) or 1
    pcm = struct.pack("<%dh" % len(mix), *[int(max(-1, min(1, x / peak * 0.89)) * 32767) for x in mix])
    wav_path = workdir / f"welcome-{name}.wav"
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm)
    m4a = workdir / f"welcome-{name}.m4a"
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", str(wav_path), str(m4a)], check=True)
    if preview_dir:
        preview_dir.mkdir(parents=True, exist_ok=True)
        (preview_dir / m4a.name).write_bytes(m4a.read_bytes())
    return m4a.read_bytes(), len(mix) / SR


# ---- Wabi-Sabi: 门楼 in the 都节 (In) scale, on a koto-like string --------

WABI_BEAT = 60.0 / 66.0
Eb4 = 311.13
WABI_MELODY = [         # same rhythm as MELODY; 6̣ (E4) lowered to E♭4
    (0.00, 1.00, D4),
    (1.00, 0.75, G4),
    (1.75, 0.25, Eb4),
    (2.00, 0.25, D4),
    (2.25, 0.25, Eb4),
    (2.50, 0.50, G4),
    (3.00, 2.00, G3),   # held longer: the 間 after it is part of the phrase
]


def koto(freq, seconds, press=0.0, seed=11):
    """A koto-like string: bright attack, upper partials dying first.

    `press` (semitones) lifts the pitch a little after the attack, the way a
    koto player presses the string behind the bridge (後押し)."""
    rnd = random.Random(seed)
    n = int(SR * seconds)
    partials = [(k, (1 / k) ** 1.1 * (1.25 if k in (2, 3) else 1.0), 2.2 + 1.6 * k)
                for k in range(1, 11)]
    phases = [rnd.uniform(0, 2 * math.pi) for _ in partials]
    out = []
    acc = 0.0
    for i in range(n):
        t = i / SR
        # pitch: struck at `freq`, pressed up `press` semitones from 0.35 s on
        bend = press * min(1.0, max(0.0, (t - 0.35) / 0.25))
        f = freq * 2 ** (bend / 12)
        acc += 2 * math.pi * f / SR
        s = 0.0
        for (k, amp, decay), ph in zip(partials, phases):
            s += amp * math.exp(-t * decay) * math.sin(k * acc + ph)
        attack = min(1.0, t / 0.003)
        out.append(s * attack)
    # the pluck itself: a very short bright noise burst
    for i in range(int(SR * 0.012)):
        out[i] += rnd.uniform(-1, 1) * 0.25 * (1 - i / (SR * 0.012))
    fade = int(SR * 0.08)
    for i in range(min(fade, n)):
        out[n - 1 - i] *= i / fade
    return out


def small_room(mix, wet=0.22):
    """A few feedback combs and an all-pass: a quiet wooden room, not a hall."""
    combs = [(int(SR * d), g) for d, g in ((0.0297, 0.78), (0.0371, 0.76), (0.0411, 0.74), (0.0437, 0.72))]
    tail = int(SR * 1.2)
    dry = mix + [0.0] * tail
    rev = [0.0] * len(dry)
    for delay, g in combs:
        buf = [0.0] * len(dry)
        for i in range(len(dry)):
            buf[i] = dry[i] + (g * buf[i - delay] if i >= delay else 0.0)
            rev[i] += buf[i] * 0.25
    d, g = int(SR * 0.005), 0.6
    ap = [0.0] * len(rev)
    for i in range(len(rev)):
        x_d = rev[i - d] if i >= d else 0.0
        y_d = ap[i - d] if i >= d else 0.0
        ap[i] = -g * rev[i] + x_d + g * y_d
    return [x + wet * y for x, y in zip(dry, ap)]


def render_wabi_sabi(workdir, preview_dir=None):
    mix = []
    last = len(WABI_MELODY) - 1
    for idx, (beat, length, freq) in enumerate(WABI_MELODY):
        press = 0.6 if idx == last else 0.0
        add(mix, beat * WABI_BEAT, koto(freq, length * WABI_BEAT + 1.1, press, seed=11 + idx), 0.5)
    return encode("wabiSabi", small_room(mix), workdir, preview_dir)


# ---- Brutalist: the anthem's first six notes, low, raw brass ---------------

BRUT_BEAT = 60.0 / 126.0
G2, C3, E3, G3b, A3, B3, C4 = 98.00, 130.81, 164.81, 196.00, 220.00, 246.94, 261.63
BRUT_MELODY = [         # pickup | bar 1 | bar 2 (4/4); C3 major, an octave down
    (0.00, 1.00, G3b),  # Со-  (pickup)
    (1.00, 2.00, C4),   # юз   (downbeat)
    (3.00, 1.50, G3b),  # не-  (dotted)
    (4.50, 0.50, A3),   # ру-
    (5.00, 2.00, B3),   # ши-  (downbeat)
    (7.00, 1.50, E3),   # мый
]
BRUT_HITS = [1.00, 5.00]   # beats that get the heavy hit


def brass(freq, seconds, seed=5):
    """Raw sawtooth brass with a sub octave: a fast, hard attack, a filter
    that opens with it, and no vibrato."""
    rnd = random.Random(seed)
    n = int(SR * seconds)
    out = []
    ph = rnd.uniform(0, 1)
    ph_sub = 0.0
    lp = 0.0
    for i in range(n):
        t = i / SR
        ph = (ph + freq / SR) % 1.0
        ph_sub = (ph_sub + freq / 2 / SR) % 1.0
        saw = 2 * ph - 1
        sub = 1.0 if ph_sub < 0.5 else -1.0
        raw = saw * 0.75 + sub * 0.35
        # one-pole low-pass whose cutoff jumps open then settles
        cutoff = 600 + 3400 * math.exp(-t * 6) + 900 * min(1, t / 0.02)
        a = 1 - math.exp(-2 * math.pi * cutoff / SR)
        lp += a * (raw - lp)
        env = min(1.0, t / 0.012) * (0.82 + 0.18 * math.exp(-t * 8))
        out.append(math.tanh(lp * env * 1.6))
    release = int(SR * 0.09)
    for i in range(min(release, n)):
        out[n - 1 - i] *= i / release
    return out


def concrete_hit(seconds=1.1):
    """A heavy, dry low hit: a pitch-dropping sine under a short noise slap."""
    out, phase = [], 0.0
    rnd = random.Random(9)
    for i in range(int(SR * seconds)):
        t = i / SR
        f = 42 + 80 * math.exp(-t * 22)
        phase += 2 * math.pi * f / SR
        s = math.sin(phase) * math.exp(-t * 4.2)
        s += rnd.uniform(-1, 1) * math.exp(-t * 60) * 0.6
        out.append(math.tanh(s * 1.4))
    return out


def render_brutalist(workdir, preview_dir=None):
    mix = []
    for idx, (beat, length, freq) in enumerate(BRUT_MELODY):
        # notes are detached: a hard stop just before the next one
        add(mix, beat * BRUT_BEAT, brass(freq, length * BRUT_BEAT * 0.92, seed=5 + idx), 0.5)
    for beat in BRUT_HITS:
        add(mix, beat * BRUT_BEAT, concrete_hit(), 0.75)
    mix.extend([0.0] * int(SR * 0.4))
    return encode("brutalist", mix, workdir, preview_dir)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("Run:")[0])
    parser.add_argument("--zh-voice", type=Path, help="the user's recorded Chinese greeting")
    parser.add_argument("--preview-dir", type=Path,
                        help="also save the Wabi-Sabi and Brutalist m4a files here, to listen to")
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
        for name, fn in (("wabiSabi", render_wabi_sabi), ("brutalist", render_brutalist)):
            data, secs = fn(work, args.preview_dir)
            print(f"{name}: {secs:.1f}s, {len(data)//1024} KB", file=sys.stderr)
            b64 = base64.b64encode(data).decode()
            lines.append(f"    static let {name}: Data = Data(base64Encoded: \"{b64}\")!")
        lines.append("}")
        OUT.write_text("\n".join(lines) + "\n")
    print("wrote", OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
