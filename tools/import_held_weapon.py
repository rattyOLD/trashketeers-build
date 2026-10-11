"""Pack the hand-free shotgun artwork at four pixels per weapon coordinate."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
image = Image.open(ROOT / 'tools/src/weapons_v57/shotgun.png').convert('RGBA')
image = image.crop(image.getbbox()).resize((804, 356), Image.Resampling.LANCZOS)
image.save(ROOT / 'source/assets/weapons/shotgun.png', optimize=True)
path = ROOT / 'source/data/weapon_sprites.json'
data = json.loads(path.read_text())
for weapon in data['sprites']:
    if weapon['icon'] == 'shotgun':
        weapon.update(size=[804, 356], grip=[156.0, 216.0], muzzle=[800.0, 74.0], support=[536.0, 244.0])
path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n')
