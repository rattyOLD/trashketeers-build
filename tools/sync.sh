#!/bin/bash
S=/tmp/claude-0/-home-claude/0fd7481c-189d-5931-953e-db25d6f3cd99/scratchpad
for d in scripts data shaders scenes assets; do rm -rf $S/t5/$d; cp -r /home/claude/raccoon/$d $S/t5/$d; done
cp /home/claude/raccoon/project.godot /home/claude/raccoon/export_presets.cfg /home/claude/raccoon/CREDITS.md $S/t5/
