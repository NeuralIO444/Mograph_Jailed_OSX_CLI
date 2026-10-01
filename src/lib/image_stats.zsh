# MJ Standard Library — ImageStats (SL-M3)
# Deterministic, bounded image signatures for loop-seam ranking and
# golden-frame regression. Uses only Python 3 stdlib. No new dependencies.
#
# image.stats: 4x4x4 RGB histogram (64 bins) + 8x8 grid averages (64 cells)
# image.compare: histogram intersection + grid similarity → 0.0-1.0 score
# loop.seams / golden.*: same signatures over a directory of PNG frames

# Shared Python signature library. Prepended to each operation's main script.
IFS= read -r -d '' MJ_PY_IMAGE_SIG <<'PY_IMAGE_SIG' || true
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

def tree_id(path):
    """Cheap identity (size, mtime) of a file, or of the regular files directly inside a directory.
    Compared before and after an operation to report honestly whether its source changed."""
    try:
        if os.path.isdir(path):
            out = []
            for n in sorted(os.listdir(path)):
                p = os.path.join(path, n)
                if os.path.isfile(p):
                    st = os.stat(p); out.append((n, st.st_size, st.st_mtime_ns))
            return tuple(out)
        st = os.stat(path)
        return (st.st_size, st.st_mtime_ns)
    except OSError:
        return None

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
            if bit_depth not in (8, 16):
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
    sample = bit_depth // 8
    channels = 3 if color_type == 2 else 4
    bpp = channels * sample
    stride = width * bpp
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
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i-bpp]) & 0xff
        elif filt == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 0xff
        elif filt == 3:
            for i in range(stride):
                a = cur[i-bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 0xff
        elif filt == 4:
            for i in range(stride):
                a = cur[i-bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i-bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 0xff
        elif filt != 0:
            raise ValueError("UNKNOWN_FILTER")
        # 16-bit samples: the high byte is the 8-bit equivalent.
        for x in range(width):
            o = x * bpp
            pixels.append((cur[o], cur[o+sample], cur[o+2*sample]))
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

def signature(path):
    w, h, px = decode_png(path)
    return {"width": w, "height": h, "histogram": compute_histogram(px), "grid": compute_grid_averages(px, w, h)}

def signature_score(a, b):
    hs = histogram_similarity(a["histogram"], b["histogram"])
    gs = grid_similarity(a["grid"], b["grid"])
    return round((hs + gs) / 2.0, 4), round(hs, 4), round(gs, 4)

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1048576), b''):
            h.update(chunk)
    return h.hexdigest()

# Frame sequences: regular, non-hidden *.png files sorted by name.
MJ_MAX_FRAMES = 2000
SIG_MAX_EDGE = 256

def list_frames(directory):
    names = sorted(n for n in os.listdir(directory)
                   if n.lower().endswith('.png') and not n.startswith('.')
                   and os.path.isfile(os.path.join(directory, n))
                   and not os.path.islink(os.path.join(directory, n)))
    if len(names) > MJ_MAX_FRAMES:
        raise ValueError("TOO_MANY_FRAMES")
    return names

def signatures_for(directory, names):
    """Signatures for frames, downscaled with sips first when available.
    Full-resolution pure-python decoding takes seconds per HD frame."""
    sips = "/usr/bin/sips"
    stage = None
    src = directory
    downscaled = False
    try:
        if names and os.access(sips, os.X_OK):
            stage = tempfile.mkdtemp(prefix="mj-sig-")
            r = subprocess.run([sips, "-Z", str(SIG_MAX_EDGE), "-s", "format", "png"]
                               + [os.path.join(directory, n) for n in names] + ["--out", stage],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if r.returncode == 0 and all(os.path.isfile(os.path.join(stage, n)) for n in names):
                src = stage
                downscaled = True
        sigs = []
        for n in names:
            try:
                sigs.append(signature(os.path.join(src, n)))
            except ValueError as e:
                raise ValueError("DECODE_FAILED: " + n + ": " + str(e))
        return sigs, downscaled
    finally:
        if stage:
            shutil.rmtree(stage, ignore_errors=True)
PY_IMAGE_SIG

image_stats_available() {
  cap_available python3 && cap_available sips && cap_available awk
}

# Run the shared library plus an operation-specific main script read from stdin.
image_sig_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s' "$MJ_PY_IMAGE_SIG" "$_main" | /usr/bin/python3 - 2>/dev/null
}

image_stats_compute() {
  local _path="$1"
  local _json=""

  cap_available python3 || return 1
  [ -f "$_path" ] && [ -r "$_path" ] || return 1

  _json=$(MJ_IMAGE_STATS_PATH="$_path" image_sig_python <<'PY_IMAGE_STATS'
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
  MJ_IMAGE_COMPARE_H1="$1" \
  MJ_IMAGE_COMPARE_G1="$2" \
  MJ_IMAGE_COMPARE_H2="$3" \
  MJ_IMAGE_COMPARE_G2="$4" \
  image_sig_python <<'PY_IMAGE_COMPARE'
try:
    a = {"histogram": json.loads(os.environ["MJ_IMAGE_COMPARE_H1"]), "grid": json.loads(os.environ["MJ_IMAGE_COMPARE_G1"])}
    b = {"histogram": json.loads(os.environ["MJ_IMAGE_COMPARE_H2"]), "grid": json.loads(os.environ["MJ_IMAGE_COMPARE_G2"])}
    score, hs, gs = signature_score(a, b)
    print(json.dumps({
        "ok": True,
        "score": score,
        "histogramSimilarity": hs,
        "gridSimilarity": gs,
    }))
except Exception as e:
    print(json.dumps({"ok": False, "code": "COMPARE_FAILED", "message": str(e)}))
PY_IMAGE_COMPARE
}
