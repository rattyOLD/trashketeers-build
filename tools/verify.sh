#!/bin/bash
# Проверка перед выкладкой (веб и APK): импорт, компиляция всех скриптов, бот проходит выживание, сюжет и рейд.
# Ноль «SCRIPT ERROR» во всех режимах — условие выкладки. Использование: GODOT=/путь/к/godot tools/verify.sh
GODOT=${GODOT:-godot}
P=source
LOG=${LOG:-/tmp/verify}
mkdir -p "$LOG"
"$GODOT" --headless --path $P --import > "$LOG/import.log" 2>&1
"$GODOT" --headless --path $P res://test/check_scripts.tscn 2>&1 | grep "CHECK checked"
fail=0
XDG_DATA_HOME="$LOG/dash-user" "$GODOT" --headless --path $P res://test/dash_regression.tscn > "$LOG/dash.log" 2>&1
if ! grep -q 'DASH_REGRESSION failures=0' "$LOG/dash.log" || grep -q 'SCRIPT ERROR' "$LOG/dash.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/landscape-user" "$GODOT" --headless --path $P res://test/landscape_audit.tscn > "$LOG/landscape.log" 2>&1
if ! grep -q 'LANDSCAPE_AUDIT failures=0' "$LOG/landscape.log" || grep -q 'SCRIPT ERROR' "$LOG/landscape.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/app-activity-user" "$GODOT" --headless --path $P res://test/app_activity_test.tscn > "$LOG/app-activity.log" 2>&1
if ! grep -q 'APP_ACTIVITY_TEST failures=0' "$LOG/app-activity.log" || grep -q 'SCRIPT ERROR' "$LOG/app-activity.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/android-perf-user" "$GODOT" --headless --path $P res://test/android_perf_regression.tscn > "$LOG/android-perf.log" 2>&1
if ! grep -q 'ANDROID_PERF_REGRESSION failures=0' "$LOG/android-perf.log" || grep -q 'SCRIPT ERROR' "$LOG/android-perf.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/app-updater-user" "$GODOT" --headless --path $P res://test/app_updater_test.tscn > "$LOG/app-updater.log" 2>&1
if ! grep -q 'APP_UPDATER_TEST failures=0' "$LOG/app-updater.log" || grep -q 'SCRIPT ERROR' "$LOG/app-updater.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/story-tester-user" "$GODOT" --headless --path $P res://test/story_tester_start_test.tscn > "$LOG/story-tester-start.log" 2>&1
if ! grep -q 'STORY_TESTER_START failures=0' "$LOG/story-tester-start.log" || grep -q 'SCRIPT ERROR' "$LOG/story-tester-start.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/manual-fire-user" "$GODOT" --headless --path $P res://test/manual_fire_test.tscn > "$LOG/manual-fire.log" 2>&1
if ! grep -q 'MANUAL_FIRE failures=0' "$LOG/manual-fire.log" || grep -q 'SCRIPT ERROR' "$LOG/manual-fire.log"; then
  fail=1
fi
XDG_DATA_HOME="$LOG/melee-user" "$GODOT" --headless --path $P res://test/melee_probe.tscn > "$LOG/melee.log" 2>&1
if ! grep -q 'MELEE_PROBE failures=0' "$LOG/melee.log" || grep -q 'SCRIPT ERROR' "$LOG/melee.log"; then
  fail=1
fi
for m in survival story raid mod:blast; do
  MODE=$m DURATION=45 timeout 300 xvfb-run -a -s "-screen 0 1280x1400x24" "$GODOT" --rendering-driver opengl3 \
    --resolution 1280x720 --path $P res://test/mode_audit.tscn > "$LOG/$m.log" 2>&1
  n=$(grep -c "SCRIPT ERROR" "$LOG/$m.log"); done_ok=$(grep -c MODE_AUDIT_DONE "$LOG/$m.log")
  echo "$m: errors=$n finished=$done_ok"
  [ "$n" != "0" ] || [ "$done_ok" != "1" ] && fail=1
done
[ $fail = 0 ] && echo "VERIFY OK" || echo "VERIFY FAILED — смотри $LOG"
