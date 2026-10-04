# Delivery QC

```text
mj qc render.mov                    against your qc_spec setting, else "web"
mj qc render.mov broadcast-us       a built-in spec
mj qc render.mov client.mjspec      a spec file
mj media.qc path=/abs/render.mov format=broadcast-eu
```

Exits 1 when a check fails, so `mj batch` and scripts can stop a bad file going out. Stock macOS only: `avmediainfo` reads the movie, `afconvert` decodes the audio.

## Built-in specs

| Spec | What it checks |
|---|---|
| `broadcast-us` | mov, ProRes, 1920x1080, 29.97 or 23.976 fps, stereo 48 kHz audio, -24 LUFS +/- 2, peak at most -2 dBFS, colour tags |
| `broadcast-eu` | mov, ProRes, 1920x1080, 25 fps, stereo 48 kHz audio, -23 LUFS +/- 1, peak at most -1 dBFS, colour tags |
| `web` | mp4 or mov, H.264 or HEVC, 48 or 44.1 kHz, -14 LUFS +/- 2, peak at most -1 dBFS |
| `social-vertical` | mp4, H.264, 1080x1920, 23.976-30 fps, at most 90 s, -14 LUFS +/- 2 |
| `prores-master` | mov, ProRes, 48 kHz audio if any, colour tags |

These are starting points; check your client's sheet.

## Spec files

UTF-8 `key = value` lines, `#` comments on their own lines (a comment after a value becomes part of the value). A leading UTF-8 BOM is ignored. If a key is repeated, the last value is used and the result carries a `DUPLICATE_SPEC_KEY` warning naming both line numbers. Lists are comma-separated.

```text
name = Client X master
container = mov
codec = prores
width = 3840
height = 2160
fps = 23.976, 24
minDuration = 15
maxDuration = 30.5
audio = required
audioChannels = 2
audioSampleRate = 48000
loudness = -24
loudnessTolerance = 1
peakMax = -2
colorTags = required
```

| Key | Values |
|---|---|
| `container` | file extensions: mov, mp4, m4v, ... |
| `codec` | prores, h264, hevc, mjpeg, png, animation, mpeg4 |
| `width`, `height` | pixels |
| `fps` | one or more frame rates |
| `minDuration`, `maxDuration` | seconds |
| `audio` | `required`, `none` or `any` |
| `audioChannels`, `audioSampleRate` | a number (a list for the sample rate) |
| `loudness`, `loudnessTolerance` | integrated LUFS, and how far off is allowed (default 1; 0 means exact) |
| `peakMax` | dBFS |
| `colorTags` | `required` or `any` |

Every value is checked before the movie is read. A typo such as `audio = requried`, a word where a number belongs, or a spec that asks for nothing is an `INVALID_SPEC` error, never a silent pass.

## How loudness is measured

ITU-R BS.1770-4 K-weighting with EBU R128 gating (absolute -70 LUFS, relative -10 LU), computed in Python on the decoded audio. It agrees with ffmpeg's ebur128 meter within 0.1 LU in the test suite. The peak is the sample peak; a true-peak meter can read up to about 0.5 dB higher on bright material, so leave headroom. Black and frozen frames are not checked. Audio shorter than 0.4 s cannot be measured and is reported as not measured. The audio is decoded to a temporary folder first (about 11 MB per minute of stereo 48 kHz); if that does not fit in free space the loudness checks are skipped and say why.
