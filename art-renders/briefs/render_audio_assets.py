#!/usr/bin/env python3
"""Compose and render the complete Data Center Tycoon audio delivery.

The score and SFX are original deterministic synthesis: no third-party samples,
loops, or preset recordings are used.  Music masters are 48 kHz / 24-bit stereo
WAV and the runtime music is encoded as high-quality Ogg Vorbis for Godot.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
import subprocess
import wave

import numpy as np
from scipy.signal import butter, sosfilt


ROOT = Path(__file__).resolve().parents[1]
FINAL = ROOT / "audio" / "final"
MASTERS = ROOT / "audio" / "work" / "masters"
SR = 48_000
RNG = np.random.default_rng(20260802)


def midi(note: float) -> float:
    return 440.0 * (2.0 ** ((note - 69.0) / 12.0))


def pan_mono(signal: np.ndarray, pan: float = 0.0) -> np.ndarray:
    pan = float(np.clip(pan, -1.0, 1.0))
    angle = (pan + 1.0) * math.pi / 4.0
    return np.column_stack((signal * math.cos(angle), signal * math.sin(angle))).astype(np.float32)


def add_event(mix: np.ndarray, signal: np.ndarray, start_s: float, gain: float = 1.0, pan: float = 0.0, wrap: bool = False) -> None:
    if signal.ndim == 1:
        signal = pan_mono(signal, pan)
    signal = signal.astype(np.float32, copy=False) * np.float32(gain)
    start = int(round(start_s * SR))
    if wrap:
        start %= len(mix)
    if start >= len(mix) or start + len(signal) <= 0:
        return
    if start < 0:
        signal = signal[-start:]
        start = 0
    available = min(len(signal), len(mix) - start)
    mix[start:start + available] += signal[:available]
    if wrap and available < len(signal):
        remainder = min(len(signal) - available, len(mix))
        mix[:remainder] += signal[available:available + remainder]


def fade_envelope(length: int, attack_s: float, release_s: float, curve: float = 1.6) -> np.ndarray:
    env = np.ones(length, dtype=np.float32)
    attack = min(length, max(1, int(attack_s * SR)))
    release = min(length, max(1, int(release_s * SR)))
    env[:attack] *= np.linspace(0.0, 1.0, attack, dtype=np.float32) ** curve
    env[-release:] *= np.linspace(1.0, 0.0, release, dtype=np.float32) ** curve
    return env


def lowpass(signal: np.ndarray, hz: float, order: int = 3) -> np.ndarray:
    return sosfilt(butter(order, hz / (SR * 0.5), btype="low", output="sos"), signal).astype(np.float32)


def highpass(signal: np.ndarray, hz: float, order: int = 3) -> np.ndarray:
    return sosfilt(butter(order, hz / (SR * 0.5), btype="high", output="sos"), signal).astype(np.float32)


def kalimba(note: float, duration: float = 1.1, brightness: float = 1.0) -> np.ndarray:
    length = int(duration * SR)
    t = np.arange(length, dtype=np.float32) / SR
    f = midi(note)
    attack = np.minimum(1.0, t / 0.004)
    body = (
        np.sin(2 * np.pi * f * t) * np.exp(-t * 3.7)
        + 0.42 * brightness * np.sin(2 * np.pi * f * 2.01 * t + 0.2) * np.exp(-t * 7.5)
        + 0.20 * brightness * np.sin(2 * np.pi * f * 3.93 * t + 1.1) * np.exp(-t * 11.0)
        + 0.08 * np.sin(2 * np.pi * f * 7.1 * t) * np.exp(-t * 17.0)
    )
    click = highpass(RNG.normal(0, 1, length).astype(np.float32), 4200) * np.exp(-t * 55.0) * 0.045
    return ((body + click) * attack * 0.72).astype(np.float32)


def bell(note: float, duration: float = 1.5, brightness: float = 1.0) -> np.ndarray:
    length = int(duration * SR)
    t = np.arange(length, dtype=np.float32) / SR
    f = midi(note)
    mod_env = np.exp(-t * 3.5)
    carrier = np.sin(2 * np.pi * f * t + (1.8 * brightness * mod_env) * np.sin(2 * np.pi * f * 2.013 * t))
    upper = 0.22 * np.sin(2 * np.pi * f * 3.99 * t + 0.6) * np.exp(-t * 5.5)
    env = np.minimum(1.0, t / 0.003) * np.exp(-t * 2.5)
    return ((carrier + upper) * env * 0.55).astype(np.float32)


def pad(note: float, duration: float, warmth: float = 1.0) -> np.ndarray:
    length = int(duration * SR)
    t = np.arange(length, dtype=np.float32) / SR
    f = midi(note)
    env = fade_envelope(length, min(0.32, duration * 0.22), min(0.48, duration * 0.28), 1.4)

    def voice(detune: float, phase: float) -> np.ndarray:
        fd = f * detune
        return (
            np.sin(2 * np.pi * fd * t + phase)
            + 0.34 * warmth * np.sin(2 * np.pi * fd * 2 * t + phase * 0.7)
            + 0.14 * np.sin(2 * np.pi * fd * 3 * t + 1.2)
        )

    left = lowpass(voice(0.997, 0.1), 4200) * env
    right = lowpass(voice(1.003, 0.7), 4400) * env
    return (np.column_stack((left, right)) * 0.20).astype(np.float32)


def bass(note: float, duration: float = 0.75, pluck: float = 1.0) -> np.ndarray:
    length = int(duration * SR)
    t = np.arange(length, dtype=np.float32) / SR
    f = midi(note)
    phase = 2 * np.pi * f * t
    body = np.sin(phase) + 0.23 * np.sin(phase * 2) + 0.08 * np.sin(phase * 3)
    env = np.minimum(1.0, t / 0.012) * np.exp(-t * (2.2 + 1.1 * pluck))
    return lowpass((body * env * 0.64).astype(np.float32), 900)


def kick(duration: float = 0.42, soft: float = 0.0) -> np.ndarray:
    length = int(duration * SR)
    t = np.arange(length, dtype=np.float32) / SR
    freq = 48.0 + (115.0 - 48.0) * np.exp(-t * 24.0)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = np.sin(phase) * np.exp(-t * (10.5 + 3.0 * soft))
    transient = lowpass(RNG.normal(0, 1, length).astype(np.float32), 1900) * np.exp(-t * 70.0) * 0.13
    return ((tone + transient) * (0.70 - 0.18 * soft)).astype(np.float32)


def rim(duration: float = 0.18) -> np.ndarray:
    length = int(duration * SR)
    t = np.arange(length, dtype=np.float32) / SR
    wood = np.sin(2 * np.pi * 960 * t) * np.exp(-t * 42) + 0.4 * np.sin(2 * np.pi * 1430 * t) * np.exp(-t * 58)
    noise = highpass(RNG.normal(0, 1, length).astype(np.float32), 3100) * np.exp(-t * 70) * 0.12
    return ((wood + noise) * 0.44).astype(np.float32)


def shaker(duration: float = 0.13, color: float = 1.0) -> np.ndarray:
    length = int(duration * SR)
    t = np.arange(length, dtype=np.float32) / SR
    noise = highpass(RNG.normal(0, 1, length).astype(np.float32), 5200)
    env = np.minimum(1, t / 0.004) * np.exp(-t * (34 / color))
    return (noise * env * 0.10).astype(np.float32)


def brush(duration: float = 0.42) -> np.ndarray:
    length = int(duration * SR)
    t = np.arange(length, dtype=np.float32) / SR
    noise = highpass(lowpass(RNG.normal(0, 1, length).astype(np.float32), 9000), 1800)
    env = np.sin(np.minimum(1, t / duration) * np.pi) ** 1.5
    return (noise * env * 0.06).astype(np.float32)


def circular_reverb(mix: np.ndarray, amount: float = 0.15) -> np.ndarray:
    wet = np.zeros_like(mix)
    for delay_s, gain, cross in ((0.071, 0.38, False), (0.113, 0.27, True), (0.173, 0.20, False), (0.257, 0.13, True)):
        delayed = np.roll(mix, int(delay_s * SR), axis=0)
        if cross:
            delayed = delayed[:, ::-1]
        wet += delayed * gain
    return (mix + wet * amount).astype(np.float32)


def tail_reverb(mix: np.ndarray, amount: float = 0.16) -> np.ndarray:
    wet = np.zeros_like(mix)
    for delay_s, gain, cross in ((0.047, 0.42, True), (0.083, 0.30, False), (0.139, 0.20, True), (0.211, 0.12, False)):
        delay = int(delay_s * SR)
        if delay >= len(mix):
            continue
        source = mix[:-delay]
        if cross:
            source = source[:, ::-1]
        wet[delay:] += source * gain
    return (mix + wet * amount).astype(np.float32)


def master(mix: np.ndarray, target_rms: float, loop: bool = False) -> np.ndarray:
    mix = mix.astype(np.float32)
    mix -= np.mean(mix, axis=0, keepdims=True)
    rms = float(np.sqrt(np.mean(mix.astype(np.float64) ** 2)))
    if rms > 1e-8:
        mix *= target_rms / rms
    mix = np.tanh(mix * 1.18) / np.tanh(1.18)
    peak = float(np.max(np.abs(mix)))
    if peak > 0.89:
        mix *= 0.89 / peak
    edge = min(int(0.010 * SR), len(mix) // 8)
    fade = np.sin(np.linspace(0, np.pi / 2, edge, dtype=np.float32)) ** 2
    mix[:edge] *= fade[:, None]
    mix[-edge:] *= fade[::-1, None]
    return np.clip(mix, -0.98, 0.98).astype(np.float32)


def music_main() -> tuple[np.ndarray, float, int]:
    bpm, bars = 96, 32
    beat = 60.0 / bpm
    bar = beat * 4
    mix = np.zeros((round(bars * bar * SR), 2), dtype=np.float32)
    progression = [
        (50, [62, 66, 69]), (47, [59, 62, 66]), (43, [55, 59, 62]), (45, [57, 61, 64]),
        (50, [62, 66, 69]), (43, [55, 59, 62]), (40, [52, 55, 59]), (45, [57, 61, 64]),
    ]
    arpeggio = [0, 1, 2, 1, 0, 1, 2, 1]
    motifs = [
        [(0.0, 74, 0.75), (1.0, 76, 0.45), (1.5, 78, 0.45), (2.0, 81, 0.8), (3.0, 78, 0.7)],
        [(0.0, 71, 0.7), (0.75, 74, 0.7), (1.5, 76, 0.45), (2.0, 74, 0.8), (3.0, 69, 0.7)],
        [(0.0, 79, 0.5), (0.5, 78, 0.5), (1.0, 76, 0.8), (2.0, 74, 0.5), (2.5, 76, 0.5), (3.0, 78, 0.8)],
        [(0.0, 73, 0.65), (0.75, 76, 0.65), (1.5, 81, 0.8), (2.5, 78, 0.45), (3.0, 76, 0.8)],
    ]
    kick_s, rim_s, shake_s, brush_s = kick(soft=0.45), rim(), shaker(), brush()
    for b in range(bars):
        start = b * bar
        root, chord = progression[b % len(progression)]
        section = b // 8
        pad_gain = (0.36, 0.48, 0.40, 0.54)[section]
        for idx, note in enumerate(chord):
            add_event(mix, pad(note - 12, bar * 1.02), start, pad_gain, wrap=True)
        for beat_idx, bass_note in ((0, root), (2, root), (3.5, root + 7)):
            if section == 0 and beat_idx == 3.5:
                continue
            add_event(mix, bass(bass_note, 0.72), start + beat_idx * beat, 0.42, pan=-0.05, wrap=True)
        for step, chord_index in enumerate(arpeggio):
            if section == 2 and step % 2:
                continue
            note = chord[chord_index] + (12 if step in (3, 7) else 0)
            add_event(mix, kalimba(note, 0.72, 0.82), start + step * beat / 2, 0.23 + section * 0.025, pan=-0.36 + 0.72 * (step / 7), wrap=True)
        if not (section == 0 and b < 2):
            for k in (0, 2):
                add_event(mix, kick_s, start + k * beat, 0.30 if section != 3 else 0.36, wrap=True)
            for k in (1, 3):
                add_event(mix, rim_s, start + k * beat, 0.24, pan=0.14, wrap=True)
            for k in range(8):
                add_event(mix, shake_s, start + k * beat / 2, 0.16 if k % 2 else 0.11, pan=0.28 if k % 2 else -0.22, wrap=True)
            add_event(mix, brush_s, start + 3.45 * beat, 0.20, pan=-0.18, wrap=True)
        if b % 2 == 0 and not (section == 0 and b == 0):
            motif = motifs[(b // 2 + section) % len(motifs)]
            transpose = 0 if section != 3 else (2 if b % 4 == 0 else 0)
            for offset, note, duration_beats in motif:
                add_event(mix, bell(note + transpose, max(0.65, duration_beats * beat + 0.55), 0.72), start + offset * beat, 0.19, pan=0.30, wrap=True)
    mix = circular_reverb(mix, 0.20)
    return master(mix, 0.145, loop=True), bpm, bars


def music_market() -> tuple[np.ndarray, float, int]:
    bpm, bars = 112, 32
    beat = 60.0 / bpm
    bar = beat * 4
    mix = np.zeros((round(bars * bar * SR), 2), dtype=np.float32)
    progression = [(45, [57, 60, 64, 67]), (50, [62, 66, 69]), (43, [55, 59, 62, 66]), (40, [52, 55, 59, 62])]
    patterns = ([0, 2, 1, 3, 2, 1, 3, 1], [0, 1, 3, 2, 1, 2, 3, 2])
    kick_s, rim_s, shake_s = kick(soft=0.65), rim(0.14), shaker(0.10, 0.8)
    for b in range(bars):
        start = b * bar
        root, chord = progression[b % 4]
        section = b // 8
        for note in chord[:3]:
            add_event(mix, pad(note - 12, bar * 1.02, 0.65), start, 0.28 if section != 2 else 0.19, wrap=True)
        pattern = patterns[(b + section) % 2]
        for step, idx in enumerate(pattern):
            octave = 12 if step in (3, 7) else 0
            add_event(mix, kalimba(chord[idx % len(chord)] + octave, 0.42, 1.15), start + step * beat / 2, 0.19, pan=-0.55 + step * 0.15, wrap=True)
        bass_pattern = [(0, root), (1.5, root + 7), (2.5, root), (3.25, root + 12)]
        for offset, note in bass_pattern:
            add_event(mix, bass(note, 0.48, 1.2), start + offset * beat, 0.36, pan=-0.08, wrap=True)
        for k in (0, 2.5):
            add_event(mix, kick_s, start + k * beat, 0.24, wrap=True)
        for k in (1, 3):
            add_event(mix, rim_s, start + k * beat, 0.20, pan=0.20, wrap=True)
        for k in range(8):
            add_event(mix, shake_s, start + k * beat / 2, 0.12 if k % 2 else 0.075, pan=0.36 if k % 2 else -0.30, wrap=True)
        if b % 4 == 3:
            for i, note in enumerate((72, 74, 78, 81)):
                add_event(mix, bell(note, 0.70, 1.0), start + (2.0 + i * 0.42) * beat, 0.13, pan=0.38 - i * 0.2, wrap=True)
    mix = circular_reverb(mix, 0.16)
    return master(mix, 0.14, loop=True), bpm, bars


def music_crisis() -> tuple[np.ndarray, float, int]:
    bpm, bars = 128, 32
    beat = 60.0 / bpm
    bar = beat * 4
    mix = np.zeros((round(bars * bar * SR), 2), dtype=np.float32)
    progression = [(38, [50, 53, 57]), (34, [46, 50, 53]), (31, [43, 46, 50]), (33, [45, 49, 52])]
    kick_s, rim_s, tick_s = kick(soft=0.15), rim(0.12), shaker(0.075, 0.65)
    for b in range(bars):
        start = b * bar
        root, chord = progression[b % 4]
        section = b // 8
        for note in chord:
            add_event(mix, pad(note - 12, bar * 1.02, 0.42), start, 0.23, wrap=True)
        for step in range(8):
            note = root + (0, 0, 7, 0, 12, 7, 3, 7)[step]
            add_event(mix, bass(note, 0.36, 1.45), start + step * beat / 2, 0.32 if step % 2 else 0.39, wrap=True)
            add_event(mix, kalimba(chord[step % 3] + 12, 0.34, 0.62), start + step * beat / 2, 0.105, pan=-0.45 + (step % 4) * 0.30, wrap=True)
            add_event(mix, tick_s, start + step * beat / 2, 0.10 if step % 2 else 0.14, pan=0.40 if step % 2 else -0.40, wrap=True)
        for k in (0, 2):
            add_event(mix, kick_s, start + k * beat, 0.34, wrap=True)
        for k in (1, 3):
            add_event(mix, rim_s, start + k * beat, 0.23, pan=0.12, wrap=True)
        if b % 4 == 0:
            for i, note in enumerate((74, 73, 69)):
                add_event(mix, bell(note, 0.62, 0.55), start + i * 0.5 * beat, 0.15, pan=0.25, wrap=True)
        if section == 3 and b % 2 == 1:
            add_event(mix, bell(81, 1.0, 0.65), start + 3.0 * beat, 0.10, pan=-0.25, wrap=True)
    mix = circular_reverb(mix, 0.11)
    return master(mix, 0.15, loop=True), bpm, bars


def noise_sweep(duration: float, start_hz: float, end_hz: float, amount: float = 1.0) -> np.ndarray:
    length = int(duration * SR)
    noise = RNG.normal(0, 1, length).astype(np.float32)
    # Crossfade a low-passed and high-passed texture to imply motion without a sample.
    lo = lowpass(noise, max(120, min(start_hz, 10_000)))
    hi = highpass(noise, max(80, min(end_hz, 10_000)))
    fade = np.linspace(0, 1, length, dtype=np.float32)
    env = fade_envelope(length, min(0.06, duration * 0.2), min(0.18, duration * 0.35), 1.2)
    return ((lo * (1 - fade) + hi * fade) * env * amount).astype(np.float32)


def tone_glide(start_hz: float, end_hz: float, duration: float, decay: float = 2.0) -> np.ndarray:
    length = int(duration * SR)
    t = np.arange(length, dtype=np.float32) / SR
    freq = np.geomspace(max(1, start_hz), max(1, end_hz), length).astype(np.float32)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    env = fade_envelope(length, 0.004, min(0.15, duration * 0.35)) * np.exp(-t * decay)
    return (np.sin(phase) * env * 0.62).astype(np.float32)


def make_sfx(name: str) -> np.ndarray:
    durations = {
        "sfx_tap": 0.14, "sfx_cash": 0.65, "sfx_build_start": 1.0,
        "sfx_build_complete": 1.45, "sfx_power_on": 1.65, "sfx_rack_install": 0.85,
        "sfx_fault": 1.2, "sfx_repair": 1.15, "sfx_retire": 1.25,
        "sfx_era": 1.7, "sfx_prestige": 2.2, "sfx_bankrupt": 2.3, "sfx_purchase": 1.15,
    }
    mix = np.zeros((int(durations[name] * SR), 2), dtype=np.float32)
    if name == "sfx_tap":
        add_event(mix, rim(0.10), 0.0, 0.48, pan=-0.08)
        add_event(mix, kalimba(79, 0.13, 0.35), 0.006, 0.20, pan=0.12)
    elif name == "sfx_cash":
        for i, note in enumerate((76, 81, 88)):
            add_event(mix, bell(note, 0.46, 1.25), 0.08 * i, 0.34 - i * 0.025, pan=-0.38 + i * 0.38)
        add_event(mix, rim(0.13), 0.015, 0.18)
    elif name == "sfx_build_start":
        add_event(mix, kick(0.28, 0.25), 0.0, 0.50)
        add_event(mix, rim(0.20), 0.09, 0.42, pan=-0.25)
        add_event(mix, rim(0.20), 0.17, 0.32, pan=0.25)
        add_event(mix, noise_sweep(0.72, 500, 4800, 0.32), 0.20, 1.0)
        add_event(mix, tone_glide(72, 132, 0.65, 0.7), 0.25, 0.28)
    elif name == "sfx_build_complete":
        add_event(mix, kick(0.42, 0.20), 0.0, 0.56)
        add_event(mix, rim(0.20), 0.08, 0.26, pan=-0.2)
        for i, note in enumerate((62, 66, 69, 74)):
            add_event(mix, bell(note, 0.9, 0.85), 0.18 + i * 0.11, 0.27, pan=-0.35 + i * 0.23)
        add_event(mix, noise_sweep(0.6, 300, 6500, 0.12), 0.25, 1.0)
    elif name == "sfx_power_on":
        add_event(mix, noise_sweep(1.05, 180, 7600, 0.24), 0.0, 1.0)
        add_event(mix, tone_glide(48, 122, 1.05, 0.35), 0.0, 0.30)
        for i, note in enumerate((62, 69, 74)):
            add_event(mix, bell(note, 1.1, 1.05), 0.58 + i * 0.14, 0.30 + i * 0.02, pan=-0.35 + i * 0.35)
        add_event(mix, bass(38, 0.9, 0.25), 0.62, 0.34)
    elif name == "sfx_rack_install":
        add_event(mix, noise_sweep(0.48, 5200, 650, 0.18), 0.0, 1.0, pan=-0.08)
        add_event(mix, rim(0.14), 0.39, 0.52, pan=-0.25)
        add_event(mix, rim(0.12), 0.49, 0.44, pan=0.25)
        add_event(mix, bell(83, 0.34, 0.65), 0.55, 0.22, pan=0.12)
    elif name == "sfx_fault":
        for start in (0.0, 0.46):
            add_event(mix, tone_glide(760, 610, 0.26, 0.8), start, 0.36, pan=-0.16)
            add_event(mix, bell(68, 0.30, 0.45), start + 0.02, 0.16, pan=0.16)
        for start, pan in ((0.19, -0.5), (0.70, 0.48), (0.82, -0.2)):
            add_event(mix, highpass(RNG.normal(0, 1, int(0.08 * SR)).astype(np.float32), 3500) * np.linspace(1, 0, int(0.08 * SR)), start, 0.08, pan=pan)
    elif name == "sfx_repair":
        add_event(mix, rim(0.14), 0.0, 0.40, pan=-0.28)
        add_event(mix, rim(0.14), 0.13, 0.34, pan=0.25)
        for i, note in enumerate((64, 67, 71, 76)):
            add_event(mix, bell(note, 0.72, 0.72), 0.27 + i * 0.10, 0.23, pan=-0.3 + i * 0.2)
    elif name == "sfx_retire":
        add_event(mix, tone_glide(210, 58, 0.82, 0.55), 0.0, 0.34)
        add_event(mix, noise_sweep(0.75, 3600, 260, 0.18), 0.0, 1.0)
        for i, note in enumerate((76, 72, 69)):
            add_event(mix, kalimba(note, 0.44, 0.75), 0.56 + i * 0.10, 0.20, pan=-0.2 + i * 0.2)
    elif name == "sfx_era":
        add_event(mix, noise_sweep(1.15, 250, 9000, 0.16), 0.0, 1.0)
        for i, note in enumerate((50, 57, 62, 66, 69, 74, 78)):
            voice = kalimba(note, 0.8, 0.9) if i < 3 else bell(note, 0.9, 1.05)
            add_event(mix, voice, 0.10 + i * 0.11, 0.22 + i * 0.012, pan=-0.55 + i * 0.18)
        add_event(mix, pad(62, 0.85, 0.8), 0.72, 0.22)
    elif name == "sfx_prestige":
        add_event(mix, noise_sweep(1.55, 320, 11_000, 0.18), 0.0, 1.0)
        notes = (62, 66, 69, 74, 78, 81, 86)
        for i, note in enumerate(notes):
            add_event(mix, bell(note, 1.3, 1.18), 0.12 + i * 0.13, 0.25 + i * 0.014, pan=-0.60 + i * 0.20)
        for note in (62, 69, 74):
            add_event(mix, pad(note, 1.15, 0.95), 0.78, 0.24)
        add_event(mix, kick(0.40, 0.55), 0.78, 0.25)
    elif name == "sfx_bankrupt":
        add_event(mix, tone_glide(148, 34, 1.75, 0.35), 0.0, 0.46)
        add_event(mix, noise_sweep(1.6, 4400, 120, 0.17), 0.0, 1.0)
        add_event(mix, kick(0.58, 0.08), 0.72, 0.55)
        for i, note in enumerate((57, 53, 50)):
            add_event(mix, bell(note, 1.0, 0.35), 0.92 + i * 0.18, 0.18, pan=-0.2 + i * 0.2)
        add_event(mix, pad(38, 0.78, 0.38), 1.30, 0.20)
    elif name == "sfx_purchase":
        for i, note in enumerate((76, 83, 88)):
            add_event(mix, bell(note, 0.8, 1.15), 0.03 + i * 0.09, 0.28, pan=-0.32 + i * 0.32)
        add_event(mix, kalimba(71, 0.65, 0.8), 0.22, 0.23, pan=-0.12)
        add_event(mix, kalimba(78, 0.65, 0.8), 0.24, 0.22, pan=0.18)
        add_event(mix, noise_sweep(0.55, 900, 8000, 0.10), 0.20, 1.0)
    mix = tail_reverb(mix, 0.12 if name not in {"sfx_prestige", "sfx_era"} else 0.20)
    return master(mix, 0.165, loop=False)


def write_wav24(path: Path, audio: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.round(np.clip(audio, -1, 1) * 8_388_607.0).astype(np.int32).reshape(-1)
    packed = np.empty((len(pcm), 3), dtype=np.uint8)
    packed[:, 0] = pcm & 0xFF
    packed[:, 1] = (pcm >> 8) & 0xFF
    packed[:, 2] = (pcm >> 16) & 0xFF
    with wave.open(str(path), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(3)
        out.setframerate(SR)
        out.writeframes(packed.tobytes())


def encode_ogg(master_path: Path, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(master_path),
        "-ac", "2", "-ar", str(SR), "-c:a", "vorbis", "-strict", "experimental", "-q:a", "8", str(output_path),
    ], check=True)


def metrics(audio: np.ndarray) -> dict[str, float]:
    rms = float(np.sqrt(np.mean(audio.astype(np.float64) ** 2)))
    peak = float(np.max(np.abs(audio)))
    edge = min(int(0.010 * SR), len(audio) // 2)
    seam = float(np.max(np.abs(audio[0] - audio[-1])))
    return {
        "duration_s": round(len(audio) / SR, 6),
        "peak_dbfs": round(20 * math.log10(max(peak, 1e-12)), 3),
        "rms_dbfs": round(20 * math.log10(max(rms, 1e-12)), 3),
        "boundary_sample_delta": round(seam, 8),
        "boundary_10ms_rms_dbfs": round(20 * math.log10(max(float(np.sqrt(np.mean(np.concatenate((audio[:edge], audio[-edge:])).astype(np.float64) ** 2))), 1e-12)), 3),
    }


def main() -> None:
    FINAL.mkdir(parents=True, exist_ok=True)
    MASTERS.mkdir(parents=True, exist_ok=True)
    report: dict[str, dict] = {}
    music_jobs = {
        "music_main": music_main,
        "music_market": music_market,
        "music_crisis": music_crisis,
    }
    for name, composer in music_jobs.items():
        print(f"Composing {name}...", flush=True)
        audio, bpm, bars = composer()
        master_path = MASTERS / f"{name}_master.wav"
        final_path = FINAL / f"{name}.ogg"
        write_wav24(master_path, audio)
        encode_ogg(master_path, final_path)
        report[name] = metrics(audio) | {
            "bpm": bpm, "bars": bars, "sample_rate": SR, "channels": 2,
            "master": str(master_path.relative_to(ROOT)), "runtime": str(final_path.relative_to(ROOT)),
            "runtime_bytes": final_path.stat().st_size,
        }
        del audio
    for name in (
        "sfx_tap", "sfx_cash", "sfx_build_start", "sfx_build_complete", "sfx_power_on",
        "sfx_rack_install", "sfx_fault", "sfx_repair", "sfx_retire", "sfx_era",
        "sfx_prestige", "sfx_bankrupt", "sfx_purchase",
    ):
        print(f"Designing {name}...", flush=True)
        audio = make_sfx(name)
        final_path = FINAL / f"{name}.wav"
        write_wav24(final_path, audio)
        report[name] = metrics(audio) | {
            "sample_rate": SR, "channels": 2, "bit_depth": 24,
            "runtime": str(final_path.relative_to(ROOT)), "runtime_bytes": final_path.stat().st_size,
        }
    (ROOT / "briefs" / "audio_render_log.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Rendered {len(report)} runtime cues.")


if __name__ == "__main__":
    main()
