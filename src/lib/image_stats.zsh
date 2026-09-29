# MJ Standard Library — ImageStats (SL-M3)
# Deterministic, bounded image signatures for loop-seam ranking.
# Uses only Python 3 stdlib (zlib, struct, json). No new dependencies.
#
# image.stats: 4x4x4 RGB histogram (64 bins) + 8x8 grid averages (64 cells)
# image.compare: histogram intersection + grid similarity → 0.0-1.0 score

image_stats_available() {
  cap_available python3 && cap_available sips && cap_available awk
}

image_stats_compute() {
  local _path="$1"
  local _json=""

  cap_available python3 || return 1
  [ -f "$_path" ] && [ -r "$_path" ] || return 1

  _json=$(MJ_IMAGE_STATS_PATH="$_path" \
    /usr/bin/python3 - <<'PY_IMAGE_STATS' 2>/dev/null
import json
import os
import struct
import sys
import zlib

def error_json(code, message):
    return json.dumps({"ok": False, "code": code, "message": message})

def decode_png(path):
    """Minimal PNG decoder using only stdlib. Returns (w, h, pixels)."""
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except Exception as e:
        raise ValueError("READ_FAILED: " + str(e))
    if len(data) < 8 or data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError("NOT_PNG")
    pos = 8
    width = height = None
    bit_depth = color_type = None
    idat_data = b''
    while pos < len(data):
        if pos + 8 > len(data):
            raise ValueError("TRUNCATED")
        length = struct.unpack('>I', data[pos:pos+4])[0]
        chunk_type = data[pos+4:pos+8]
        if pos + 12 + length > len(data):
            raise ValueError("TRUNCATED")
        chunk_data = data[pos+8:pos+8+length]
        pos += 12 + length
        if chunk_type == b'IHDR':
            width, height, bit_depth, color_type, comp, filt, interlace = struct.unpack('>IIBBBBB', chunk_data)
            if bit_depth != 8:
                raise ValueError("UNSUPPORTED_BIT_DEPTH")
            if color_type not in (2, 6):
                raise ValueError("UNSUPPORTED_COLOR_TYPE")
            if interlace != 0:
                raise ValueError("INTERLACED_NOT_SUPPORTED")
        elif chunk_type == b'IDAT':
            idat_data += chunk_data
        elif chunk_type == b'IEND':
            break
    if width is None:
        raise ValueError("MISSING_IHDR")
    try:
        raw = zlib.decompress(idat_data)
    except Exception:
        raise ValueError("DECOMPRESS_FAILED")
    channels = 3 if color_type == 2 else 4
    stride = width * channels
    pixels = []
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        if pos >= len(raw):
            raise ValueError("TRUNCATED_SCANLINES")
        filt = raw[pos]; pos += 1
        if pos + stride > len(raw):
            raise ValueError("TRUNCATED_SCANLINES")
        cur = bytearray(raw[pos:pos+stride]); pos += stride
        if filt == 1:
            for i in range(channels, stride):
                cur[i] = (cur[i] + cur[i-channels]) & 0xff
        elif filt == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 0xff
        elif filt == 3:
            for i in range(stride):
                a = cur[i-channels] if i >= channels else 0
                cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 0xff
        elif filt == 4:
            for i in range(stride):
                a = cur[i-channels] if i >= channels else 0
                b = prev[i]
                c = prev[i-channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 0xff
        elif filt != 0:
            raise ValueError("UNKNOWN_FILTER")
        for x in range(width):
            pixels.append((cur[x*channels], cur[x*channels+1], cur[x*channels+2]))
        prev = cur
    return width, height, pixels

def compute_histogram(pixels, bins_per_channel=4):
    bins = [0] * (bins_per_channel ** 3)
    scale = 256 // bins_per_channel
    for r, g, b in pixels:
        ri = min(r // scale, bins_per_channel - 1)
        gi = min(g // scale, bins_per_channel - 1)
        bi = min(b // scale, bins_per_channel - 1)
        idx = (ri * bins_per_channel + gi) * bins_per_channel + bi
        bins[idx] += 1
    return bins

def compute_grid_averages(pixels, width, height, grid_size=8):
    sums = [[[0, 0, 0, 0] for _ in range(grid_size)] for _ in range(grid_size)]
    for y in range(height):
        for x in range(width):
            r, g, b = pixels[y * width + x]
            gx = min(x * grid_size // width, grid_size - 1)
            gy = min(y * grid_size // height, grid_size - 1)
            sums[gy][gx][0] += r
            sums[gy][gx][1] += g
            sums[gy][gx][2] += b
            sums[gy][gx][3] += 1
    result = []
    for gy in range(grid_size):
        for gx in range(grid_size):
            rs, gs, bs, cnt = sums[gy][gx]
            if cnt > 0:
                result.append([rs // cnt, gs // cnt, bs // cnt])
            else:
                result.append([0, 0, 0])
    return result

def main():
    path = os.environ.get("MJ_IMAGE_STATS_PATH", "")
    if not path:
        print(error_json("INVALID_PATH", "No path provided"))
        return
    try:
        width, height, pixels = decode_png(path)
    except ValueError as e:
        print(error_json("DECODE_FAILED", str(e)))
        return
    except Exception as e:
        print(error_json("DECODE_FAILED", "Unexpected: " + str(e)))
        return
    hist = compute_histogram(pixels)
    grid = compute_grid_averages(pixels, width, height)
    print(json.dumps({
        "ok": True,
        "width": width,
        "height": height,
        "pixelCount": len(pixels),
        "histogramBins": 64,
        "histogram": hist,
        "gridSize": 8,
        "gridAverages": grid,
    }))

main()
PY_IMAGE_STATS
) || return 1

  printf '%s' "$_json"
}

image_stats_compare() {
  local _hist1="$1"
  local _grid1="$2"
  local _hist2="$3"
  local _grid2="$4"

  MJ_IMAGE_COMPARE_H1="$_hist1" \
  MJ_IMAGE_COMPARE_G1="$_grid1" \
  MJ_IMAGE_COMPARE_H2="$_hist2" \
  MJ_IMAGE_COMPARE_G2="$_grid2" \
  /usr/bin/python3 - <<'PY_IMAGE_COMPARE' 2>/dev/null
import json
import os

def histogram_similarity(h1, h2):
    total = sum(h1)
    if total == 0:
        return 1.0 if sum(h2) == 0 else 0.0
    return sum(min(a, b) for a, b in zip(h1, h2)) / total

def grid_similarity(g1, g2):
    if not g1 or not g2 or len(g1) != len(g2):
        return 0.0
    total_diff = 0
    for (r1, x1, b1), (r2, x2, b2) in zip(g1, g2):
        total_diff += abs(r1 - r2) + abs(x1 - x2) + abs(b1 - b2)
    max_diff = len(g1) * 255 * 3
    return 1.0 - (total_diff / max_diff) if max_diff > 0 else 1.0

try:
    h1 = json.loads(os.environ["MJ_IMAGE_COMPARE_H1"])
    g1 = json.loads(os.environ["MJ_IMAGE_COMPARE_G1"])
    h2 = json.loads(os.environ["MJ_IMAGE_COMPARE_H2"])
    g2 = json.loads(os.environ["MJ_IMAGE_COMPARE_G2"])
    hs = histogram_similarity(h1, h2)
    gs = grid_similarity(g1, g2)
    score = (hs + gs) / 2.0
    print(json.dumps({
        "ok": True,
        "score": round(score, 4),
        "histogramSimilarity": round(hs, 4),
        "gridSimilarity": round(gs, 4),
    }))
except Exception as e:
    print(json.dumps({"ok": False, "code": "COMPARE_FAILED", "message": str(e)}))
PY_IMAGE_COMPARE
}
