# 音频交付 QA

- 运行时 cue：16/16
- 失败：0
- 音乐：48 kHz、立体声、高质量 Vorbis、无缝边界检查
- 音效：48 kHz、立体声、24-bit PCM WAV
- 频谱联系表：`../audio/review/music_spectrum_contact.png`

| cue | codec | duration | peak | RMS | status |
|---|---|---:|---:|---:|---|
| `music_main` | vorbis | 80.000s | -1.01 dBFS | -14.19 dBFS | PASS |
| `music_market` | vorbis | 68.572s | -1.95 dBFS | -14.24 dBFS | PASS |
| `music_crisis` | vorbis | 60.000s | -1.95 dBFS | -13.66 dBFS | PASS |
| `sfx_tap` | pcm_s24le | 0.140s | -3.43 dBFS | -13.34 dBFS | PASS |
| `sfx_cash` | pcm_s24le | 0.650s | -2.53 dBFS | -12.95 dBFS | PASS |
| `sfx_build_start` | pcm_s24le | 1.000s | -1.01 dBFS | -14.59 dBFS | PASS |
| `sfx_build_complete` | pcm_s24le | 1.450s | -1.01 dBFS | -13.58 dBFS | PASS |
| `sfx_power_on` | pcm_s24le | 1.650s | -1.01 dBFS | -14.11 dBFS | PASS |
| `sfx_rack_install` | pcm_s24le | 0.850s | -1.01 dBFS | -14.28 dBFS | PASS |
| `sfx_fault` | pcm_s24le | 1.200s | -1.01 dBFS | -14.12 dBFS | PASS |
| `sfx_repair` | pcm_s24le | 1.150s | -1.03 dBFS | -13.03 dBFS | PASS |
| `sfx_retire` | pcm_s24le | 1.250s | -1.01 dBFS | -12.93 dBFS | PASS |
| `sfx_era` | pcm_s24le | 1.700s | -1.01 dBFS | -13.82 dBFS | PASS |
| `sfx_prestige` | pcm_s24le | 2.200s | -1.01 dBFS | -14.11 dBFS | PASS |
| `sfx_bankrupt` | pcm_s24le | 2.300s | -1.24 dBFS | -12.91 dBFS | PASS |
| `sfx_purchase` | pcm_s24le | 1.150s | -1.01 dBFS | -14.31 dBFS | PASS |
