#!/bin/bash
# Копирует рабочий проект в репозиторий: source/ (без .godot). Запускать из корня репозитория.
DEST="$(cd "$(dirname "$0")/.." && pwd)/source"
rm -rf "$DEST" && mkdir -p "$DEST"
cd /home/claude/raccoon && tar --exclude=.godot -cf - . | tar -xf - -C "$DEST"
