#!/usr/bin/env python3
"""Validate runtime audio and create music spectrum review images."""

from __future__ import annotations

import json
import math
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
DELIVERY = ROOT / "art-renders" / "audio" / "final"
BRIEFS = ROOT / "art-renders" / "briefs"
REVIEW = ROOT / "art-renders" / "audio" / "review"
RUNTIME_MANIFEST = ROOT / "assets" / "audio" / "manifest.json"
SR = 48_000


def probe(path: Path) -> dict:
    result = subprocess.run([
        "ffprobe", "-v", "error", "-show_entries",
        "format=duration:stream=codec_name,sample_rate,channels,bits_per_sample",
        "-of", "json", str(path),
    ], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def decoded_music_metrics(path: Path) -> dict[str, float]:
    result = subprocess.run([
        "ffmpeg", "-v", "error", "-i", str(path), "-ac", "2", "-ar", str(SR),
        "-f", "f32le", "-acodec", "pcm_f32le", "-",
    ], check=True, capture_output=True)
    audio = np.frombuffer(result.stdout, dtype="<f4").reshape(-1, 2)
    edge = min(int(0.010 * SR), len(audio) // 4)
    peak = float(np.max(np.abs(audio)))
    rms = float(np.sqrt(np.mean(audio.astype(np.float64) ** 2)))
    seam = float(np.max(np.abs(audio[0] - audio[-1])))
    return {
        "decoded_samples": len(audio),
        "decoded_duration_s": len(audio) / SR,
        "decoded_peak_dbfs": 20 * math.log10(max(peak, 1e-12)),
        "decoded_rms_dbfs": 20 * math.log10(max(rms, 1e-12)),
        "decoded_boundary_sample_delta": seam,
        "decoded_boundary_10ms_rms_dbfs": 20 * math.log10(max(float(np.sqrt(np.mean(np.concatenate((audio[:edge], audio[-edge:])).astype(np.float64) ** 2))), 1e-12)),
    }


def make_spectra() -> Path:
    REVIEW.mkdir(parents=True, exist_ok=True)
    names = ["music_main", "music_market", "music_crisis"]
    rendered: list[tuple[str, Path]] = []
    for name in names:
        source = ROOT / "art-renders" / "audio" / "work" / "masters" / f"{name}_master.wav"
        output = REVIEW / f"{name}_spectrum.png"
        subprocess.run([
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(source),
            "-lavfi", "showspectrumpic=s=1400x420:legend=disabled:mode=combined:color=fiery:scale=cbrt",
            "-frames:v", "1", str(output),
        ], check=True)
        rendered.append((name, output))
    title_h, row_h, width = 48, 454, 1400
    sheet = Image.new("RGB", (width, title_h + row_h * len(rendered)), "#2B3A55")
    draw = ImageDraw.Draw(sheet)
    title_font = ImageFont.load_default(size=24)
    label_font = ImageFont.load_default(size=18)
    draw.text((16, 12), "DATA CENTER TYCOON · MUSIC SPECTRUM QA", fill="#FFF6E8", font=title_font)
    for index, (name, path) in enumerate(rendered):
        y = title_h + index * row_h
        draw.text((12, y + 4), name, fill="#FFF6E8", font=label_font)
        spectrum = Image.open(path).convert("RGB")
        sheet.paste(spectrum, (0, y + 34))
    output = REVIEW / "music_spectrum_contact.png"
    sheet.save(output, format="PNG", optimize=True)
    return output


def main() -> None:
    manifest = json.loads(RUNTIME_MANIFEST.read_text(encoding="utf-8"))["items"]
    render_log = json.loads((BRIEFS / "audio_render_log.json").read_text(encoding="utf-8"))
    expected = {Path(spec["path"]).name for spec in manifest.values()}
    actual = {path.name for path in DELIVERY.iterdir() if path.is_file() and not path.name.startswith(".")}
    entries = []
    failures = []
    for cue_id, spec in manifest.items():
        filename = Path(spec["path"]).name
        path = DELIVERY / filename
        if not path.exists():
            failures.append(f"missing {filename}")
            continue
        info = probe(path)
        stream = info["streams"][0]
        entry = {
            "cue_id": cue_id,
            "filename": filename,
            "kind": spec["kind"],
            "codec": stream["codec_name"],
            "sample_rate": int(stream["sample_rate"]),
            "channels": int(stream["channels"]),
            "bits_per_sample": int(stream.get("bits_per_sample") or 0),
            "duration_s": float(info["format"]["duration"]),
            "bytes": path.stat().st_size,
            "render_metrics": render_log[cue_id],
        }
        if spec["kind"] == "music":
            entry["decoded_metrics"] = decoded_music_metrics(path)
        passed = entry["sample_rate"] == SR and entry["channels"] == 2
        if spec["kind"] == "music":
            passed = passed and entry["codec"] == "vorbis" and entry["decoded_metrics"]["decoded_boundary_sample_delta"] < 0.01
        else:
            passed = passed and entry["codec"] == "pcm_s24le" and entry["bits_per_sample"] == 24
        entry["pass"] = passed
        if not passed:
            failures.append(f"format/seam check failed: {filename}")
        entries.append(entry)
    extras = sorted(actual - expected)
    missing = sorted(expected - actual)
    if extras:
        failures.append("unexpected runtime files: " + ", ".join(extras))
    if missing:
        failures.append("missing runtime files: " + ", ".join(missing))
    spectrum = make_spectra()
    report = {"expected_count": len(expected), "actual_count": len(actual), "failures": failures, "entries": entries, "spectrum_contact": str(spectrum.relative_to(ROOT))}
    (BRIEFS / "audio_qa_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# 音频交付 QA", "",
        f"- 运行时 cue：{len(entries)}/{len(expected)}", f"- 失败：{len(failures)}",
        "- 音乐：48 kHz、立体声、高质量 Vorbis、无缝边界检查",
        "- 音效：48 kHz、立体声、24-bit PCM WAV",
        f"- 频谱联系表：`../{spectrum.relative_to(ROOT / 'art-renders')}`", "",
        "| cue | codec | duration | peak | RMS | status |", "|---|---|---:|---:|---:|---|",
    ]
    for entry in entries:
        metrics = entry["render_metrics"]
        lines.append(f"| `{entry['cue_id']}` | {entry['codec']} | {entry['duration_s']:.3f}s | {metrics['peak_dbfs']:.2f} dBFS | {metrics['rms_dbfs']:.2f} dBFS | {'PASS' if entry['pass'] else 'FAIL'} |")
    if failures:
        lines.extend(["", "## 失败项", ""] + [f"- {failure}" for failure in failures])
    (BRIEFS / "audio_qa_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Audio QA: {len(entries) - len(failures)}/{len(expected)} passed; failures={len(failures)}")
    if failures:
        for failure in failures:
            print("FAIL", failure)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
