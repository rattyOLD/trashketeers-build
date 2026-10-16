#!/usr/bin/env python3
"""Independent inbox contract checks; does not import the drawing generator."""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path

from PIL import Image, ImageStat

REQUIRED_MATERIALS = {
    "cobble_gold", "cobble_worn", "rose_path", "marble", "lawn", "garden_soil",
    "stone_wall", "plaster", "step_riser", "roof_red",
}


def pixels(image):
    return image.get_flattened_data() if hasattr(image,"get_flattened_data") else image.getdata()


def validate(root):
    errors, report = [], {"brief":"v36", "materials":{}, "checked_png":0}
    def require(ok, message):
        if not ok:
            errors.append(message)
    palette=Image.open(root/"palettes/bank.png").convert("RGB")
    colors=set(pixels(palette))
    require(palette.height==1 and 48<=palette.width<=64, "Bank palette must be a 48–64 color strip")
    require(len(colors)==palette.width, "Palette contains duplicate colors")
    manifest=json.loads((root/"materials/manifest.json").read_text())
    require(manifest.get("pixels_per_metre")==32, "World density is not 32 px/m")
    groups={}
    names=set()
    for f in manifest["files"]:
        name=f["file"]
        require(name not in names, f"Duplicate manifest entry {name}")
        names.add(name)
        path=root/"materials"/name
        require(path.parent==root/"materials", f"Unexpected asset path {name}")
        if not path.exists():
            errors.append(f"Missing {name}")
            continue
        with Image.open(path) as probe:
            probe.verify()
        im=Image.open(path)
        report["checked_png"]+=1
        require(im.size==(64,64),f"{name}: wrong native dimensions")
        require((f["width"],f["height"])==im.size,f"{name}: manifest dimensions")
        require(hashlib.sha256(path.read_bytes()).hexdigest()==f["sha256"],f"{name}: SHA256 mismatch")
        require(path.stat().st_size==f["bytes"],f"{name}: size mismatch")
        require(f.get("size_m")==[2.,2.],f"{name}: wrong 2×2m footprint")
        require(f.get("anchor_px")==[0,0],f"{name}: texture needs a UV-origin anchor")
        require(f.get("tileable_x") and f.get("tileable_y"),f"{name}: repeat contract missing")
        rgba=im.convert("RGBA")
        require(set(pixels(rgba.getchannel("A")))=={255},f"{name}: surface must be opaque")
        if f["role"]=="albedo":
            used_colors=set(pixels(im.convert("RGB")))
            require(used_colors<=colors,f"{name}: colors outside Bank palette")
            require(len(used_colors)>=3,f"{name}: material lacks color steps")
            groups.setdefault(f["material"],[]).append((name,rgba,f))
            if f.get("normal_map"):
                require(f["normal_map"] in {v["file"] for v in manifest["files"]},f"{name}: missing normal link")
        else:
            require(f["role"]=="normal",f"{name}: unknown role")
            xyz=[tuple(c/255*2-1 for c in p) for p in pixels(im.convert("RGB"))]
            require(all(abs(math.sqrt(sum(c*c for c in p))-1)<.015 for p in xyz),f"{name}: normal length")
            require(all(p[2]>.8 for p in xyz),f"{name}: unreasonable/inverted normal Z")
    require(set(groups)==REQUIRED_MATERIALS,"Missing or extra material family")
    pairs=0
    for material,files in groups.items():
        require(2<=len(files)<=3,f"{material}: expected 2–3 variants")
        require(len({f[2]["sha256"] for f in files})==len(files),f"{material}: duplicate variants")
        for (an,a,_),(bn,b,_) in itertools.product(files,repeat=2):
            require(a.crop((63,0,64,64)).tobytes()==b.crop((0,0,1,64)).tobytes(),f"X seam {an}/{bn}")
            require(a.crop((0,63,64,64)).tobytes()==b.crop((0,0,64,1)).tobytes(),f"Y seam {an}/{bn}")
            pairs+=2
        # Check edge neighborhoods too: a pasted uniform border would produce
        # anomalous flat strips even if first/last pixels matched exactly.
        for name,im,_ in files:
            edge=im.convert("RGB").crop((0,0,4,64))
            require(len(set(pixels(edge)))>=3,f"{name}: artificially flat seam strip")
        values=[ImageStat.Stat(f[1].convert("L")).mean[0] for f in files]
        report["materials"][material]={"variants":len(files),"mean_luma":[round(v,3) for v in values]}
    # Semantic guard against the v33 error: a complete atlas of dry grass must
    # not pass only because its dimensions and hashes are internally valid.
    if "lawn" in groups:
        for name,im,_ in groups["lawn"]:
            mean=ImageStat.Stat(im.convert("RGB")).mean
            require(mean[1]>mean[0]*1.06 and mean[1]>mean[2]*1.15,f"{name}: lawn not living green")
    if "marble" in groups:
        require(report["materials"]["marble"]["mean_luma"][0]>190,"Marble should read as pale stone")
    require(names=={p.name for p in (root/"materials").glob("*.png")},"PNG files omitted from manifest")
    report.update(edge_pair_checks=pairs,errors=errors,ok=not errors)
    return report


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[1]/"astra/inbox/hd2d_test")
    parser.add_argument("--report",type=Path)
    args=parser.parse_args()
    report=validate(args.root)
    if args.report:
        args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps(report,ensure_ascii=False,indent=2))
    print("V36_MATERIALS_OK" if report["ok"] else "V36_MATERIALS_FAILED")
    raise SystemExit(0 if report["ok"] else 1)
