#!/usr/bin/env python3
"""Normalize v30 high-resolution sources to the brief's game-sized PNGs."""
import argparse
import json
from pathlib import Path

from PIL import Image


def visible_bounds(image):
    return image.getchannel("A").point(lambda value: 255 if value > 16 else 0).getbbox()


def normalize_sprite(source, size, padding):
    bounds = visible_bounds(source)
    if bounds is None:
        raise ValueError("Empty sprite")
    sprite = source.crop(bounds)
    sprite.thumbnail((size[0] - padding * 2, size[1] - padding * 2), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size)
    canvas.alpha_composite(sprite, ((size[0] - sprite.width) // 2, (size[1] - sprite.height) // 2))
    return canvas


def normalize_sheet(source, entry):
    count = entry["frames"]
    width, height = entry["target"]
    cell_width = width // count
    frames = [source.crop(region) for region in entry["regions"]]
    anchors = [(source.width * (index + 0.5) / count - region[0], source.height / 2 - region[1])
               for index, region in enumerate(entry["regions"])]
    radius_x = radius_y = 0.0
    for frame, anchor in zip(frames, anchors):
        bounds = visible_bounds(frame)
        if bounds is None:
            raise ValueError("Empty animation frame")
        radius_x = max(radius_x, anchor[0] - bounds[0], bounds[2] - anchor[0])
        radius_y = max(radius_y, anchor[1] - bounds[1], bounds[3] - anchor[1])
    scale = min((cell_width / 2 - 4) / radius_x, (height / 2 - 4) / radius_y)
    sheet = Image.new("RGBA", (width, height))
    for index, (frame, anchor) in enumerate(zip(frames, anchors)):
        resized = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.Resampling.LANCZOS)
        cell = Image.new("RGBA", (cell_width, height))
        cell.alpha_composite(resized, (round(cell_width / 2 - anchor[0] * scale), round(height / 2 - anchor[1] * scale)))
        sheet.alpha_composite(cell, (index * cell_width, 0))
    return sheet


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Output directory; sources are preserved")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    if args.output.resolve() == root:
        parser.error("Choose a separate output directory to preserve the high-resolution sources")
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((root / "manifest.json").read_text())
    for entry in manifest["files"]:
        source = Image.open(root / entry["name"]).convert("RGBA")
        if list(source.size) != entry["native"]:
            raise ValueError(f"Unexpected source dimensions: {entry['name']}")
        if entry["frames"] > 1:
            result = normalize_sheet(source, entry)
        else:
            padding = 1 if entry["name"] == "flail_link.png" else 3
            result = normalize_sprite(source, tuple(entry["target"]), padding)
        path = args.output / entry["name"]
        result.save(path, optimize=True)
        print(f"{path.name}: {result.width}x{result.height}, {entry['frames']} frame(s)")


if __name__ == "__main__":
    main()
