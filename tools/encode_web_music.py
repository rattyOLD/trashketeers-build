#!/usr/bin/env python3
"""Produce the streamed Web tracks; APK uses the original Ogg assets.

48 kHz stereo AAC-LC avoids the low-rate mono AAC decoding error in Chromium.
Use the original full tracks, with faststart metadata for streamed playback.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "source/web/music"
TARGET.mkdir(exist_ok=True)
for name in ("menu", "battle", "raid", "knife", "win", "boss"):
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(ROOT / "source/assets/audio/music" / f"{name}.ogg"),
        "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k",
        "-movflags", "+faststart", str(TARGET / f"{name}.m4a"),
    ], check=True)
