#!/bin/bash
S=/tmp/claude-0/-home-claude/0fd7481c-189d-5931-953e-db25d6f3cd99/scratchpad
cd $S && bash sync.sh
cd $S/t5 && timeout 300 ../godot --headless --path . --import > ../imp_t5.log 2>&1
timeout 120 ../godot --headless --path . res://test/check_all.tscn > ../check_t5.log 2>&1
timeout 300 ../godot --headless --path . res://test/smoke.tscn > ../smoke_t5.log 2>&1
rm -rf build/web && mkdir -p build/web
timeout 500 ../godot --headless --path . --export-release "Web" build/web/index.html > ../exp_t5.log 2>&1
cd $S && python3 make_site.py $S/t5/build/web > make_site.log 2>&1
echo DONE > build_main.done
