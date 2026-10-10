#!/bin/bash
# Проверка перед выкладкой (веб и APK): импорт, компиляция всех скриптов, бот проходит выживание, сюжет и рейд.
# Ноль «SCRIPT ERROR» во всех режимах — условие выкладки. Использование: GODOT=/путь/к/godot tools/verify.sh
GODOT=${GODOT:-godot}
set -o pipefail
P=${1:-source}
LOG=${LOG:-/tmp/verify}
mkdir -p "$LOG"
export XDG_DATA_HOME=${XDG_DATA_HOME:-$LOG/user}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$LOG/cache}
fail=0
if ! timeout 300 "$GODOT" --headless --path "$P" --import > "$LOG/import.log" 2>&1 || grep -q 'SCRIPT ERROR' "$LOG/import.log"; then
  echo "VERIFY FAILED — импорт ресурсов: $LOG/import.log"
  exit 1
fi
if ! "$GODOT" --headless --path "$P" res://test/check_scripts.tscn > "$LOG/scripts.log" 2>&1 || ! grep -q 'CHECK checked .*failed 0' "$LOG/scripts.log" || grep -q 'SCRIPT ERROR' "$LOG/scripts.log"; then
  fail=1
fi
grep 'CHECK checked' "$LOG/scripts.log"
XDG_DATA_HOME="$LOG/brief-user" "$GODOT" --headless --path "$P" res://test/brief_completion_test.tscn > "$LOG/brief.log" 2>&1
if ! grep -q 'BRIEF_COMPLETION failures=0' "$LOG/brief.log" || grep -q 'SCRIPT ERROR' "$LOG/brief.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/dash-user" "$GODOT" --headless --path "$P" res://test/dash_regression.tscn > "$LOG/dash.log" 2>&1
if ! grep -q 'DASH_REGRESSION failures=0' "$LOG/dash.log" || grep -q 'SCRIPT ERROR' "$LOG/dash.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/landscape-user" "$GODOT" --headless --path "$P" res://test/landscape_audit.tscn > "$LOG/landscape.log" 2>&1
if ! grep -q 'LANDSCAPE_AUDIT failures=0' "$LOG/landscape.log" || grep -q 'SCRIPT ERROR' "$LOG/landscape.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/app-activity-user" "$GODOT" --headless --path "$P" res://test/app_activity_test.tscn > "$LOG/app-activity.log" 2>&1
if ! grep -q 'APP_ACTIVITY_TEST failures=0' "$LOG/app-activity.log" || grep -q 'SCRIPT ERROR' "$LOG/app-activity.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/android-perf-user" "$GODOT" --headless --path "$P" res://test/android_perf_regression.tscn > "$LOG/android-perf.log" 2>&1
if ! grep -q 'ANDROID_PERF_REGRESSION failures=0' "$LOG/android-perf.log" || grep -q 'SCRIPT ERROR' "$LOG/android-perf.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/app-updater-user" "$GODOT" --headless --path "$P" res://test/app_updater_test.tscn > "$LOG/app-updater.log" 2>&1
if ! grep -q 'APP_UPDATER_TEST failures=0' "$LOG/app-updater.log" || grep -q 'SCRIPT ERROR' "$LOG/app-updater.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/story-tester-user" "$GODOT" --headless --path "$P" res://test/story_tester_start_test.tscn > "$LOG/story-tester-start.log" 2>&1
if ! grep -q 'STORY_TESTER_START failures=0' "$LOG/story-tester-start.log" || grep -q 'SCRIPT ERROR' "$LOG/story-tester-start.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/manual-fire-user" "$GODOT" --headless --path "$P" res://test/manual_fire_test.tscn > "$LOG/manual-fire.log" 2>&1
if ! grep -q 'MANUAL_FIRE failures=0' "$LOG/manual-fire.log" || grep -q 'SCRIPT ERROR' "$LOG/manual-fire.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/melee-user" "$GODOT" --headless --path "$P" res://test/melee_probe.tscn > "$LOG/melee.log" 2>&1
if ! grep -q 'MELEE_PROBE failures=0' "$LOG/melee.log" || grep -q 'SCRIPT ERROR' "$LOG/melee.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/levelup-user" xvfb-run -a -s "-screen 0 1700x900x24" "$GODOT" --display-driver x11 --rendering-driver opengl3 --resolution 1560x720 --path "$P" res://test/levelup_layout_test.tscn > "$LOG/levelup.log" 2>&1
if ! grep -q 'LEVELUP_LAYOUT failures=0' "$LOG/levelup.log" || grep -q 'SCRIPT ERROR' "$LOG/levelup.log"; then
  fail=1
fi
# Узкий телефон (iPhone в «альбомной» вкладке): окно должно ужаться и встать по центру.
XDG_DATA_HOME="$LOG/levelup-narrow-user" xvfb-run -a -s "-screen 0 1700x900x24" "$GODOT" --display-driver x11 --rendering-driver opengl3 --resolution 923x420 --path "$P" res://test/levelup_layout_test.tscn > "$LOG/levelup-narrow.log" 2>&1
if ! grep -q 'LEVELUP_LAYOUT failures=0' "$LOG/levelup-narrow.log" || grep -q 'SCRIPT ERROR' "$LOG/levelup-narrow.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/ui-v32-user" xvfb-run -a -s "-screen 0 1280x1400x24" "$GODOT" --display-driver x11 --rendering-driver opengl3 --resolution 1280x720 --path "$P" res://test/ui_v32_test.tscn > "$LOG/ui-v32.log" 2>&1
if ! grep -q 'UI_V32 failures=0' "$LOG/ui-v32.log" || grep -q 'SCRIPT ERROR' "$LOG/ui-v32.log"; then
  fail=1
fi
UI_NATIVE_A13=1 UI_RENDER_SCALE=0.75 XDG_DATA_HOME="$LOG/ui-a13-user" xvfb-run -a -s "-screen 0 1280x1400x24" "$GODOT" --display-driver x11 --rendering-driver opengl3 --resolution 1280x720 --path "$P" res://test/ui_v32_test.tscn > "$LOG/ui-a13.log" 2>&1
if ! grep -q 'UI_V32 failures=0' "$LOG/ui-a13.log" || grep -q 'SCRIPT ERROR' "$LOG/ui-a13.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/hand-grip-user" "$GODOT" --headless --path "$P" res://test/hand_grip_test.tscn > "$LOG/hand-grip.log" 2>&1
if ! grep -q 'HAND_GRIP failures=0' "$LOG/hand-grip.log" || grep -q 'SCRIPT ERROR' "$LOG/hand-grip.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/menu-motion-user" timeout 90 "$GODOT" --headless --path "$P" res://test/menu_preview_motion_test.tscn > "$LOG/menu-motion.log" 2>&1
if ! grep -q 'MENU_PREVIEW_MOTION failures=0' "$LOG/menu-motion.log" || grep -q 'SCRIPT ERROR' "$LOG/menu-motion.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/combat-polish-user" timeout 90 "$GODOT" --headless --path "$P" res://test/combat_polish_test.tscn > "$LOG/combat-polish.log" 2>&1
if ! grep -q 'COMBAT_POLISH failures=0' "$LOG/combat-polish.log" || grep -q 'SCRIPT ERROR' "$LOG/combat-polish.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/combat-polish-layout-user" timeout 90 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --display-driver x11 --rendering-driver opengl3 --resolution 1280x720 --path "$P" res://test/combat_polish_layout_test.tscn > "$LOG/combat-polish-layout.log" 2>&1
if ! grep -q 'COMBAT_POLISH_LAYOUT failures=0' "$LOG/combat-polish-layout.log" || grep -q 'SCRIPT ERROR' "$LOG/combat-polish-layout.log"; then
  fail=1
fi
for m in survival story raid mod:blast; do
  MODE=$m DURATION=45 timeout 300 xvfb-run -a -s "-screen 0 1280x1400x24" "$GODOT" --display-driver x11 --rendering-driver opengl3 \
    --resolution 1280x720 --path "$P" res://test/mode_audit.tscn > "$LOG/$m.log" 2>&1
  n=$(grep -c "SCRIPT ERROR" "$LOG/$m.log"); done_ok=$(grep -c MODE_AUDIT_DONE "$LOG/$m.log")
  echo "$m: errors=$n finished=$done_ok"
  [ "$n" != "0" ] || [ "$done_ok" != "1" ] && fail=1
done
for hero in sniper_f medic_f; do
  MODE=survival HERO="$hero" NATIVE_A13=1 SOAK=1 WAVE=30 SCALE=1 DURATION=30 timeout 300 xvfb-run -a -s "-screen 0 1280x1400x24" "$GODOT" --display-driver x11 --rendering-driver opengl3 \
    --resolution 1280x720 --path "$P" res://test/mode_audit.tscn > "$LOG/a13-$hero.log" 2>&1
  n=$(grep -c "SCRIPT ERROR" "$LOG/a13-$hero.log"); done_ok=$(grep -c MODE_AUDIT_DONE "$LOG/a13-$hero.log")
  echo "a13-$hero: errors=$n finished=$done_ok"
  [ "$n" != "0" ] || [ "$done_ok" != "1" ] && fail=1
done
if [ "$fail" = 0 ]; then
  echo "VERIFY OK"
else
  echo "VERIFY FAILED — смотри $LOG"
  exit 1
fi
