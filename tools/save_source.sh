#!/bin/bash
# Копирует рабочий проект в репозиторий: source/ (без .godot). Запускать из корня репозитория.
rsync -a --delete --exclude .godot /home/claude/raccoon/ "$(dirname "$0")/../source/"
