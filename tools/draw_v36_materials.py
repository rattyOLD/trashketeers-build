#!/usr/bin/env python3
"""Native 96px Bank surfaces. No resampling or painted-image conversion.

All coordinates, clusters and palette entries live on the final pixel grid.
The generated look-development board is a visual reference, not an input.
"""
import hashlib
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "astra/inbox/hd2d_test"
PREVIEW = ROOT / "astra/previews/v36"
SIZE = 96
PERIOD = SIZE - 1
RAMPS = {
    "stone": ["6c5550", "8c8784", "a49b8d", "bab09e", "cec3ad", "dfd5bf"],
    "gold": ["8b715c", "a28b69", "b49a73", "c3a97f", "d0b68b", "ddc69c"],
    "rose": ["806b70", "8c8784", "ac8887", "bd9993", "cda99f", "dbbdb0"],
    "marble": ["a49b8d", "bab09e", "cbc5b7", "d9d3c3", "e4decd", "eee7d5"],
    "green": ["203b2a", "365332", "4e684c", "5e7652", "70885d", "859967", "98b94c", "c6d77c"],
    "earth": ["613c35", "6c5550", "7b6254", "8b715c", "9d8268", "a28b69"],
    "red": ["67474f", "805157", "975e5b", "ae7265", "c28a75", "e3a16c"],
}
COLORS = {k: [tuple(bytes.fromhex(c)) for c in v] for k, v in RAMPS.items()}
MASTER = json.loads((OUT/"palettes/colors.json").read_text())
PALETTE = [tuple(bytes.fromhex(h.lstrip("#"))) for h in MASTER["colors"]]
assert len(PALETTE) == len(set(PALETTE)) == 64
assert all(c in PALETTE for ramp in COLORS.values() for c in ramp)


def noise(x, y, salt=0):
    # Hash lattice; only used to place coherent clusters, never RGB noise.
    n = (int(x) * 374761393 + int(y) * 668265263 + salt * 1442695041) & 0xffffffff
    n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
    return ((n ^ (n >> 16)) & 0xffff) / 65535


def field(x, y, cells, seed):
    x, y = x / PERIOD * cells, y / PERIOD * cells
    xi, yi = math.floor(x), math.floor(y)
    u, v = x - xi, y - yi
    u, v = u * u * (3 - 2 * u), v * v * (3 - 2 * v)
    a, b = noise(xi % cells, yi % cells, seed), noise((xi + 1) % cells, yi % cells, seed)
    c, d = noise(xi % cells, (yi + 1) % cells, seed), noise((xi + 1) % cells, (yi + 1) % cells, seed)
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v


def masonry(x, y, kind):
    if kind.startswith("cobble"):
        # Toroidal staggered, individually shaped stones. Voronoi cell borders
        # follow adjacent stones, rather than rectangular brick courses.
        distances = []
        for row in range(-1, 8):
            for col in range(-1, 8):
                rr, cc = row % 6, col % 7
                # Periodic stagger: an even number of horizontal courses.
                cy = row * (PERIOD / 6) + (noise(cc, rr, 10)-.5)*2.0
                cx = col * (PERIOD / 7) + ((row % 6) % 2)*(PERIOD / 14) + (noise(cc, row%6, 11)-.5)*2.0
                d = math.hypot(x-cx, (y-cy)*.9)
                distances.append((d, cc, row%6))
        distances.sort()
        (d0, col, row), (d1, _, _) = distances[:2]
        edge = (d1-d0)*.5
        grain = field(x, y, 19, 44)
        if edge < .42:
            return COLORS["gold"][1], .3
        if edge < 1.0:
            return COLORS["gold"][2], .48
        tone = 3 + (noise(col,row,35)>.56)
        if grain < .22:
            tone = max(2,tone-1)
        elif grain > .78:
            tone = min(5,tone+1)
        return COLORS["gold"][tone], .66+.025*(tone-3)
    elif kind in ("rose_path", "marble"):
        courses, columns = 3, 3
    else:
        courses, columns = 4, 3
    fy = y / PERIOD * courses
    row = math.floor(fy) % courses
    stagger = (row % 2) * 0.5 if kind != "marble" else 0
    fx = x / PERIOD * columns + stagger
    col = math.floor(fx) % columns
    u, v = fx % 1, fy % 1
    # 1px joints, chamfered corners and subtly eroded edges.
    dx, dy = min(u, 1-u) * PERIOD / columns, min(v, 1-v) * PERIOD / courses
    corner = (dx + dy - 1.25) * 0.71
    edge = min(dx, dy, corner)
    seed = row * 13 + col * 31
    grain = field(x, y, 14, 44)
    if kind == "marble":
        if edge < 0.36:
            return COLORS["gold"][2], 0.39
        if edge < 0.8:
            return COLORS["marble"][2], 0.57
        vein = abs(field(x, y, 3, 7) - 0.49)
        tone = 4 if vein > 0.028 else 3
        if grain > 0.74 and vein < 0.08:
            tone = 3
        return COLORS["marble"][tone], 0.66
    ramp = "gold" if kind.startswith("cobble") else "rose" if kind == "rose_path" else "stone"
    if edge < 0.45:
        return COLORS[ramp][0 if kind != "stone_wall" else 1], 0.26
    if edge < 1.15:
        return COLORS[ramp][2], 0.46
    tone = 3 + (noise(col, row, 49) > 0.63) - (noise(col, row, 35) < 0.17)
    if grain > 0.76:
        tone = min(5, tone + 1)
    elif grain < 0.24:
        tone = max(2, tone - 1)
    return COLORS[ramp][tone], 0.67 + 0.07 * (tone - 3)


def base_surface(kind):
    im = Image.new("RGBA", (SIZE, SIZE))
    heights = [[0.] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            xx, yy = x % PERIOD, y % PERIOD
            f = field(xx, yy, 7, 71)
            if kind in ("cobble_gold", "cobble_worn", "rose_path", "marble", "stone_wall"):
                color, h = masonry(xx, yy, kind)
            elif kind == "lawn":
                broad = field(xx, yy, 18, 17)
                tone = 3 if broad < .52 else 4
                if broad < .15:
                    tone = 2
                elif broad > .84:
                    tone = 5
                color, h = COLORS["green"][tone], 0.42 + tone * 0.025
            elif kind == "garden_soil":
                soil = field(xx, yy, 19, 2)
                tone = 2 if soil < .56 else 3
                if soil < .14:
                    tone = 1
                elif soil > .86:
                    tone = 4
                color, h = COLORS["earth"][tone], 0.37 + tone * 0.025
            elif kind == "plaster":
                patch = field(xx, yy, 12, 6)
                tone = 4 if patch > 0.37 else 3
                if patch > .82:
                    tone = 5
                color, h = COLORS["marble"][tone], 0.55
            elif kind == "step_riser":
                tone = 3 if field(xx,yy,15,6) < 0.34 else 4
                h = 0.6
                if 32 <= yy <= 34 or 76 <= yy <= 78:
                    tone, h = 2, 0.4
                elif yy in (31, 75):
                    tone, h = 5, 0.65
                color = COLORS["stone"][tone]
            elif kind == "roof_red":
                # Convex rolls repeat every 9px; the relief, not a painted sun,
                # supplies directionality when normal-mapped in 3D.
                row = int(yy / (PERIOD/4))
                fx = (xx / (PERIOD/7) + (row % 2) * 0.5) % 1
                fy = (yy % (PERIOD/4)) / (PERIOD/4)
                arch = math.sin(math.pi * fx)
                height = arch * 0.34
                if fy < 0.08 or (fy < .22 and arch < .35):
                    tone, h = 0, 0.25
                elif fy < 0.15:
                    tone, h = 2, 0.5
                else:
                    tone = min(4, 1 + int(arch * 3) + (f > 0.8))
                    h = 0.45 + height
                color = COLORS["red"][tone]
            else:
                raise ValueError(kind)
            im.putpixel((x, y), (*color, 255))
            heights[y][x] = h
    return im, heights


def variants(kind):
    base, heights = base_surface(kind)
    result = []
    for variant in range(3):
        im, ht = base.copy(), [r[:] for r in heights]
        p = im.load()
        rng = random.Random(724 + variant * 811 + sum(map(ord, kind)))
        # Boundary neighborhoods remain common across all three variants.
        # Details are sparse clusters in the interior, not a noisy filter.
        if kind in ("cobble_gold", "cobble_worn", "rose_path", "stone_wall"):
            ramp = "gold" if kind.startswith("cobble") else "rose" if kind == "rose_path" else "stone"
            count = 38 if kind == "cobble_worn" else 16
            for _ in range(count):
                cx, cy = rng.randrange(10, 85), rng.randrange(10, 85)
                size = rng.randrange(3, 7) if kind == "cobble_worn" else rng.randrange(1, 4)
                for dy in range(-size, size + 1):
                    for dx in range(-size-1, size + 2):
                        x, y = cx + dx, cy + dy
                        if dx * dx / (size+1)**2 + dy * dy / size**2 > 1:
                            continue
                        if ht[y][x] > 0.6:
                            tone = 4 if kind == "cobble_worn" else (3 if variant != 1 else 2)
                            p[x, y] = (*COLORS[ramp][tone], 255)
                            ht[y][x] = 0.69 if kind == "cobble_worn" else 0.61
            if kind == "rose_path" or kind == "stone_wall":
                # One short hairline fracture, kept off the tiling boundary.
                x, y = 28 + variant * 12, 22 + variant * 17
                for i in range(9):
                    if ht[y+i][x+i//3] > 0.6:
                        p[x+i//3, y+i] = (*COLORS[ramp][2], 255)
                        ht[y+i][x+i//3] = 0.53
        elif kind == "lawn":
            for _ in range(85):
                x, y = rng.randrange(8, 87), rng.randrange(9, 87)
                tone = rng.choice([3, 4, 5])
                for dx, dy in [(0, 0), (1, -1), (1, -2), (-1, -1)]:
                    p[x+dx, y+dy] = (*COLORS["green"][tone], 255)
            # Quiet, 4px clover accents; no giant flowers or dry grass.
            for x, y in [(18+variant*4, 29), (63, 62-variant*6), (40, 78), (75-variant*5,24)]:
                for dx, dy in [(-1,-1),(0,-1),(-1,0),(1,0),(2,0),(1,1),(0,2),(-1,2)]:
                    p[x+dx,y+dy] = (*COLORS["green"][5],255)
                p[x,y+1] = (*COLORS["green"][3],255)
        elif kind == "garden_soil":
            for _ in range(60):
                x, y = rng.randrange(8, 87), rng.randrange(8, 87)
                for dx,dy in [(0,0),(1,0),(0,1)]:
                    p[x+dx,y+dy] = (*COLORS["earth"][rng.choice([2,3,4])],255)
            for _ in range(4):
                x, y = rng.randrange(12, 83), rng.randrange(12, 83)
                p[x,y] = (*COLORS["stone"][2],255)
                p[x+1,y] = (*COLORS["stone"][3],255)
        elif kind in ("plaster", "step_riser", "marble", "roof_red"):
            ramp = "red" if kind == "roof_red" else "marble" if kind in ("plaster", "marble") else "stone"
            for _ in range(28):
                x, y = rng.randrange(9, 85), rng.randrange(9, 85)
                tone = 3 if kind != "roof_red" else 2
                for dx, dy in [(0,0),(1,0),(1,1)]:
                    if ht[y+dy][x+dx] > 0.52:
                        p[x+dx,y+dy] = (*COLORS[ramp][tone],255)
            if kind == "marble":
                x, y = 15 + variant * 22, 18 + variant * 10
                for i in range(21):
                    xx, yy = x + i // 2, y + i
                    if ht[yy][xx] > 0.6:
                        p[xx,yy] = (*COLORS["marble"][3],255)
        result.append((im, ht))
    return result


def normal_map(heights):
    im = Image.new("RGB", (SIZE,SIZE))
    for y in range(SIZE):
        for x in range(SIZE):
            # OpenGL tangent space (+Y up): Godot's normal_map_invert_y=false.
            dx = (heights[y%PERIOD][(x+1)%PERIOD] - heights[y%PERIOD][(x-1)%PERIOD]) * 0.9
            dy = (heights[(y+1)%PERIOD][x%PERIOD] - heights[(y-1)%PERIOD][x%PERIOD]) * 0.9
            nx, ny, nz = -dx, dy, 1.
            length = math.sqrt(nx*nx+ny*ny+1)
            im.putpixel((x,y), tuple(round((v/length*0.5+0.5)*255) for v in (nx,ny,nz)))
    return im


def file_info(path, **extra):
    im = Image.open(path)
    return {"file":path.name, "width":im.width, "height":im.height, "format":im.mode,
            "bytes":path.stat().st_size, "sha256":hashlib.sha256(path.read_bytes()).hexdigest(), **extra}


def write_json(path, data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")


def main():
    for folder in (OUT/"materials", OUT/"palettes", PREVIEW):
        folder.mkdir(parents=True, exist_ok=True)
    # Later prop deliveries may use previously unused palette slots. Preserve
    # that master palette when reproducing the 48px/m materials.
    definition=OUT/"palettes/colors.json"
    palette_colors=PALETTE
    if definition.exists():
        palette_colors=[tuple(bytes.fromhex(c.lstrip("#"))) for c in json.loads(definition.read_text())["colors"]]
    palette = Image.new("RGB",(64,1))
    palette.putdata(palette_colors)
    palette.save(OUT/"palettes/bank.png")
    manifest={"schema_version":1,"brief":"v36","revision":"native-96-48pxm","studio":"TrashSquad · Beer Party Studio",
              "pixels_per_metre":48,"palette":"../palettes/bank.png","color_space":"sRGB",
              "texture_filter":"nearest_with_mipmaps","texture_repeat":"enabled",
              "cast_shadows_baked":False,"directional_light_baked":False,
              "variant_edge_compatibility":"all ordered pairs, horizontal and vertical, within a material",
              "normal_convention":"OpenGL +Y; normal_map_invert_y=false; import as linear normal data",
              "files":[]}
    materials=[("cobble_gold","Золотистая брусчатка"),("cobble_worn","Вытертая брусчатка"),
               ("rose_path","Розовый камень"),("marble","Мрамор и золото"),
               ("lawn","Зелёный газон"),("garden_soil","Земля клумб"),
               ("stone_wall","Каменная кладка"),("plaster","Штукатурка"),
               ("step_riser","Бок ступени"),("roof_red","Красная черепица")]
    # Review-only magnification: native delivery files never resized.
    board=Image.new("RGB",(1110,10*316+76),(24,30,35))
    draw=ImageDraw.Draw(board)
    fontpath="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    font=ImageFont.truetype(fontpath,16)
    small=ImageFont.truetype(fontpath,13)
    draw.text((24,14),"TRASH SQUAD · BANK · v36 / native 96 × 96 · 48 px/m",font=font,fill=(238,216,170))
    draw.text((24,42),"Variants at 2× · randomized 3×3 repeat at 1× on right · nearest only",font=small,fill=(168,180,185))
    for row,(kind,label) in enumerate(materials):
        images=[]
        for v,(im,ht) in enumerate(variants(kind)):
            path=OUT/"materials"/f"{kind}_{v+1:02d}.png"
            im.save(path)
            entry=file_info(path,material=kind,variant=v+1,role="albedo",size_m=[2.,2.],
                            authored_size_px=[96,96],resampled=False,
                            anchor_px=[0,0],anchor_uv=[0.,0.],anchor_kind="surface_uv_origin",
                            tileable_x=True,tileable_y=True,roughness=0.92 if kind!="marble" else 0.48,
                            metallic=0.,palette="../palettes/bank.png")
            if kind in ("cobble_gold","cobble_worn","roof_red"):
                np=path.with_name(path.stem+"_n.png")
                normal_map(ht).save(np)
                entry["normal_map"]=np.name
                entry["normal_scale"]=0.65
                manifest["files"].append(file_info(np,material=kind,variant=v+1,role="normal",
                    size_m=[2.,2.],anchor_px=[0,0],anchor_uv=[0.,0.],tileable_x=True,tileable_y=True,
                    color_space="linear_data",normal_convention="OpenGL +Y"))
            manifest["files"].append(entry)
            images.append(im)
        yy=82+row*316
        draw.text((24,yy),f"{row+1:02d}  {label}",font=font,fill=(226,211,178))
        for v,im in enumerate(images):
            board.paste(im.resize((192,192),Image.Resampling.NEAREST).convert("RGB"),(24+v*206,yy+26))
        rng=random.Random(313+row)
        tiled=Image.new("RGB",(288,288))
        for y in range(3):
            for x in range(3):
                tiled.paste(images[rng.randrange(3)].convert("RGB"),(x*SIZE,y*SIZE))
        board.paste(tiled,(728,yy+26))
    write_json(OUT/"materials/manifest.json",manifest)
    palette_manifest={
        "schema_version":1,"brief":"v36","studio":"TrashSquad · Beer Party Studio",
        "files":[file_info(OUT/"palettes/bank.png",role="environment_palette",colors=64,
             size_m=None,anchor_px=None,not_a_world_surface=True)],
        "ramps":{k:["#"+s for s in v] for k,v in RAMPS.items()},
        "pending":["chars.png — will be delivered with the character batch; not substituted by rejected v35 drafts"]}
    if definition.exists():
        palette_manifest=json.loads((OUT/"palettes/manifest.json").read_text())
        palette_manifest["files"]=[file_info(OUT/"palettes/bank.png",role="environment_palette",colors=64,
             size_m=None,anchor_px=None,not_a_world_surface=True)]
    write_json(OUT/"palettes/manifest.json",palette_manifest)
    board.save(PREVIEW/"materials_review.png")
    print(f"DRAW_V36_MATERIALS_OK albedo=30 normals=9 colors={len(PALETTE)}")


if __name__ == "__main__":
    main()
