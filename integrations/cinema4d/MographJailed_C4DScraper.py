# MographJailed Cinema 4D scene scraper (MJ_C4D_SCRAPE_1). READ-ONLY.
#
#   c4dpy MographJailed_C4DScraper.py <scene.c4d> <output-folder>
#
# Loads the scene, reads settings and asset paths, and writes ONE new JSON receipt into the output folder
# (never overwriting an existing file). It never saves, edits or renders the scene.
#
# STATUS: written against the documented c4d Python API but NOT YET RUN against a real Cinema 4D (headless
# c4dpy stops at a licence prompt until licensing is configured once by hand). Every read is guarded so a
# getter that fails on your version yields null/empty instead of aborting. After licensing, run it once and
# report any field it could not fill. scripts/check-c4d-scraper-readonly.sh keeps it read-only.

import json
import os
import sys
import time

import c4d

MAX_TEXTURES, MAX_MATERIALS, MAX_CAMERAS, MAX_TAKES = 2000, 500, 200, 200

# Render-engine ids (c4d.RDATA_RENDERENGINE values). Redshift's id is fixed by Maxon.
RENDERER_REDSHIFT = 1036219


def guarded(fn, default=None):
    """Run a read; on any failure return the default so one bad getter never aborts the scrape."""
    try:
        return fn()
    except Exception:
        return default


def iter_objects(first):
    """Depth-first walk of the object tree (read-only)."""
    stack = [first] if first else []
    while stack:
        obj = stack.pop()
        while obj:
            yield obj
            child = obj.GetDown()
            if child:
                stack.append(obj.GetNext())
                obj = child
            else:
                obj = obj.GetNext()


def renderer_name(rd):
    engine = guarded(lambda: rd[c4d.RDATA_RENDERENGINE])
    if engine == RENDERER_REDSHIFT:
        return "redshift"
    if engine == guarded(lambda: c4d.RDATA_RENDERENGINE_PHYSICAL):
        return "physical"
    if engine == guarded(lambda: c4d.RDATA_RENDERENGINE_STANDARD):
        return "standard"
    return "other"


def material_type(mat):
    # Redshift materials report a plugin id; anything with the standard material id is "standard".
    pid = guarded(lambda: mat.GetType())
    if pid == guarded(lambda: c4d.Mmaterial):
        return "standard"
    name = guarded(lambda: mat.GetTypeName(), "") or ""
    return "redshift" if "redshift" in name.lower() else "other"


def scrape(scene_path):
    doc = c4d.documents.LoadDocument(scene_path, c4d.SCENEFILTER_OBJECTS | c4d.SCENEFILTER_MATERIALS)
    if doc is None:
        raise RuntimeError("Cinema 4D could not load the scene")
    rd = doc.GetActiveRenderData()
    fps = guarded(lambda: float(doc.GetFps()), 0.0)
    start = guarded(lambda: int(doc.GetMinTime().GetFrame(fps)), 0)
    end = guarded(lambda: int(doc.GetMaxTime().GetFrame(fps)), 0)

    passes = []
    if rd is not None:
        post = guarded(lambda: rd.GetFirstMultipass())
        while post:
            passes.append({"name": guarded(lambda: post.GetName(), "")})
            post = post.GetNext()

    cameras = []
    objects = 0
    for obj in iter_objects(doc.GetFirstObject()):
        objects += 1
        if guarded(lambda: obj.GetType()) == guarded(lambda: c4d.Ocamera) and len(cameras) < MAX_CAMERAS:
            cameras.append({"name": guarded(lambda: obj.GetName(), ""), "active": False})
    base = guarded(lambda: doc.GetRenderBaseDraw().GetSceneCamera(doc))
    active_name = guarded(lambda: base.GetName()) if base else None
    for cam in cameras:
        cam["active"] = (cam["name"] == active_name)

    materials = []
    mat = doc.GetFirstMaterial()
    while mat and len(materials) < MAX_MATERIALS:
        materials.append({"name": guarded(lambda: mat.GetName(), ""), "type": material_type(mat)})
        mat = mat.GetNext()

    takes = []
    td = guarded(lambda: doc.GetTakeData())
    if td:
        main = td.GetMainTake()
        current = td.GetCurrentTake()
        stack = [main] if main else []
        while stack and len(takes) < MAX_TAKES:
            take = stack.pop()
            while take and len(takes) < MAX_TAKES:
                takes.append({"name": guarded(lambda: take.GetName(), ""), "active": take == current})
                child = take.GetDown()
                if child:
                    stack.append(take.GetNext())
                    take = child
                else:
                    take = take.GetNext()

    textures = []
    truncated = False
    assets = guarded(lambda: c4d.documents.GetAllAssetsNew(doc, False, ""), None)
    if isinstance(assets, tuple):          # (result, list) in some versions
        assets = assets[-1]
    for item in assets or []:
        if len(textures) >= MAX_TEXTURES:
            truncated = True
            break
        path = item.get("filename") if isinstance(item, dict) else None
        if not path:
            continue
        exists = bool(item.get("exists", True)) if isinstance(item, dict) else True
        textures.append({"path": path, "resolved": item.get("assetname") or path, "missing": not exists, "absolute": os.path.isabs(path)})

    out = {
        "schema": "MJ_C4D_SCRAPE_1", "scraperVersion": "1.0",
        "scenePath": os.path.abspath(scene_path), "sceneName": os.path.basename(scene_path),
        "scrapedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "c4dVersion": str(guarded(lambda: c4d.GetC4DVersion(), "")),
        "fps": fps, "startFrame": start, "endFrame": end,
        "width": guarded(lambda: int(rd[c4d.RDATA_XRES]), 0), "height": guarded(lambda: int(rd[c4d.RDATA_YRES]), 0),
        "renderer": renderer_name(rd) if rd is not None else "other",
        "outputPath": guarded(lambda: str(rd[c4d.RDATA_PATH]), ""),
        "outputFormat": str(guarded(lambda: rd[c4d.RDATA_FORMAT], "")),
        "multipass": bool(guarded(lambda: rd[c4d.RDATA_MULTIPASS_ENABLE], False)),
        "passes": passes, "cameras": cameras, "takes": takes, "materials": materials, "textures": textures,
        "objects": objects, "truncated": truncated,
    }
    return out


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: c4dpy MographJailed_C4DScraper.py <scene.c4d> <output-folder>\n")
        return 64
    scene, outdir = argv[1], argv[2]
    if not os.path.isfile(scene):
        sys.stderr.write("scene not found: %s\n" % scene)
        return 66
    if not os.path.isdir(outdir):
        sys.stderr.write("output folder not found: %s\n" % outdir)
        return 66
    doc = scrape(scene)
    base = os.path.splitext(os.path.basename(scene))[0]
    stamp = time.strftime("%Y%m%d-%H%M%S", time.gmtime())
    path = os.path.join(outdir, "%s.%s.c4dscrape.json" % (base, stamp))
    n = 1
    while os.path.exists(path):
        n += 1
        path = os.path.join(outdir, "%s.%s-%d.c4dscrape.json" % (base, stamp, n))
    with open(path, "x", encoding="utf-8") as f:       # "x": never overwrite
        json.dump(doc, f, indent=1, sort_keys=True)
        f.write("\n")
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
