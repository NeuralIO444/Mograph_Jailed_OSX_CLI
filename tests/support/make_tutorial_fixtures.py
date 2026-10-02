#!/usr/bin/env python3
# Builds the small, realistic sandbox that the tutorials in docs/guides use, under the folder given as argv[1]:
#   projects/   two projects and a Cinema 4D scene (placeholder bytes: they are only copied and hashed)
#   media/      footage the scrapes refer to
#   receipts/   two scrapes of "Spring Promo" (before and after a day of work) and one Cinema 4D scene receipt
import copy, json, os, sys

root = sys.argv[1]
def mk(p, data=b""):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "wb").write(data)

mk(root + "/projects/Spring Promo/Spring Promo.aep", b"spring-promo-v1")
mk(root + "/projects/Summer Sale/Summer Sale.aep", b"summer-sale")
mk(root + "/projects/Logo Sting/Logo Sting.c4d", b"logo-sting-scene")
for f in ("bg.mov", "logo.psd", "music.wav"):
    mk(root + "/media/" + f, b"x")
M = root + "/media/"

def layer(i, name, typ="AVLayer", src="", sid=0, spath="", fx=(), ex=(), font=""):
    l = {"index": i, "name": name, "type": typ, "enabled": True, "solo": False, "locked": False, "hasVideo": True, "hasAudio": False,
         "sourceName": src, "sourcePath": spath, "sourceId": sid, "effects": [{"name": n, "matchName": m} for n, m in fx],
         "markers": 0, "numProperties": 4, "numKeyframedProperties": 0, "expressions": [{"propertyPath": p, "expression": e} for p, e in ex]}
    if font: l["font"] = font
    return l

v1 = {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.0", "projectPath": root + "/projects/Spring Promo/Spring Promo.aep", "projectName": "Spring Promo.aep",
      "scrapedAt": "2026-10-01T09:00:00Z", "aeVersion": "26.5.0", "numItems": 6, "fonts": ["Brandon Grotesque", "Inter"],
      "footage": [{"id": 10, "name": "bg.mov", "path": M + "bg.mov", "missing": False, "hasVideo": True, "hasAudio": False},
                  {"id": 11, "name": "logo.psd", "path": M + "logo.psd", "missing": False, "hasVideo": True, "hasAudio": False}],
      "comps": [
          {"id": 1, "name": "Main", "width": 1920, "height": 1080, "pixelAspect": 1.0, "frameRate": 24, "duration": 10.0, "numLayers": 3, "layers": [
              layer(1, "Title", "TextLayer", font="Brandon Grotesque", fx=[("Glow", "ADBE Glo2")], ex=[("Transform/Position", 'thisComp.layer("Logo").transform.position')]),
              layer(2, "Lower Third", src="Lower Third", sid=2),
              layer(3, "Backdrop", src="bg.mov", sid=10, spath=M + "bg.mov")]},
          {"id": 2, "name": "Lower Third", "width": 1920, "height": 1080, "pixelAspect": 1.0, "frameRate": 24, "duration": 10.0, "numLayers": 2, "layers": [
              layer(1, "Name", "TextLayer", font="Inter", fx=[("Sapphire Glow", "S_Glow")]),
              layer(2, "Logo", src="logo.psd", sid=11, spath=M + "logo.psd")]}]}
v2 = copy.deepcopy(v1)
v2["scrapedAt"] = "2026-10-01T16:30:00Z"
v2["footage"][1]["missing"] = True
main = v2["comps"][0]
main["frameRate"] = 30
main["layers"][0]["expressions"][0]["expression"] = 'thisComp.layer("Logo Mark").transform.position'
main["layers"].insert(0, layer(1, "Flash", "AVLayer", fx=[("Fast Blur", "ADBE Fast Blur")]))
for i, l in enumerate(main["layers"], 1): l["index"] = i
v2["comps"].append({"id": 3, "name": "Outro", "width": 1920, "height": 1080, "pixelAspect": 1.0, "frameRate": 30, "duration": 3.0, "numLayers": 0, "layers": []})
os.makedirs(root + "/receipts", exist_ok=True)
json.dump(v1, open(root + "/receipts/spring.20261001T090000Z.scrape.json", "w"), indent=1)
json.dump(v2, open(root + "/receipts/spring.20261001T163000Z.scrape.json", "w"), indent=1)

# An After Effects project that uses the Cinema 4D scene, for the bridge tutorial.
sting_ae = {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.0", "projectPath": root + "/projects/Summer Sale/Summer Sale.aep", "projectName": "Summer Sale.aep",
            "scrapedAt": "2026-10-02T09:00:00Z", "aeVersion": "26.5.0", "numItems": 3, "fonts": [], "footage": [{"id": 20, "name": "Logo Sting.c4d", "path": root + "/projects/Logo Sting/Logo Sting.c4d", "missing": False, "hasVideo": True, "hasAudio": False}],
            "comps": [{"id": 1, "name": "Sting", "width": 1920, "height": 1080, "pixelAspect": 1.0, "frameRate": 30, "duration": 3.0, "numLayers": 1, "layers": [
                layer(1, "3D Logo", src="Logo Sting.c4d", sid=20, spath=root + "/projects/Logo Sting/Logo Sting.c4d")]}]}
json.dump(sting_ae, open(root + "/receipts/summer.20261002T090000Z.scrape.json", "w"), indent=1)
c4d = {"schema": "MJ_C4D_SCRAPE_1", "scraperVersion": "1.0", "scenePath": root + "/projects/Logo Sting/Logo Sting.c4d", "sceneName": "Logo Sting.c4d",
       "scrapedAt": "2026-10-02T08:00:00Z", "c4dVersion": "2026.3", "fps": 24, "startFrame": 0, "endFrame": 71, "width": 1920, "height": 1080,
       "renderer": "redshift", "outputPath": "", "outputFormat": "PNG", "multipass": True, "passes": [{"name": "Beauty"}, {"name": "Depth"}],
       "cameras": [{"name": "Camera", "active": True}], "takes": [{"name": "Main", "active": True}],
       "materials": [{"name": "Chrome", "type": "redshift"}, {"name": "Old Plastic", "type": "standard"}],
       "textures": [{"path": "tex/chrome_normal.png", "resolved": "", "missing": True, "absolute": False}, {"path": "/Users/ana/Desktop/env.hdr", "resolved": "/Users/ana/Desktop/env.hdr", "missing": False, "absolute": True}], "objects": 18}
json.dump(c4d, open(root + "/receipts/logo.20261002T080000Z.c4dscrape.json", "w"), indent=1)
print("fixtures ready in", root)
