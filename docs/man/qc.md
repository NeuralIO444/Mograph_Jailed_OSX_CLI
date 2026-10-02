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

`key = value` lines, `#` comments. Lists are comma-separated.

```text
name = Client X master
container = mov
codec = prores                 prores, h264, hevc, mjpeg, png, animation, mpeg4
width = 3840
height = 2160
fps = 23.976, 24
minDuration = 15
maxDuration = 30.5
audio = required               required, none or any
audioChannels = 2
audioSampleRate = 48000
loudness = -24                 integrated LUFS
loudnessTolerance = 1
peakMax = -2                   dBFS
colorTags = required
```

## How loudness is measured

ITU-R BS.1770-4 K-weighting with EBU R128 gating (absolute -70 LUFS, relative -10 LU), computed in Python on the decoded audio. It agrees with ffmpeg's ebur128 meter within 0.1 LU in the test suite. The peak is the sample peak; a true-peak meter can read up to about 0.5 dB higher on bright material, so leave headroom. Black and frozen frames are not checked.
