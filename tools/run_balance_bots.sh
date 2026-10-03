#!/bin/bash
# Бот-балансёр выживания (source/test/balance_bot.tscn): N забегов новичка параллельно, итог — волна смерти.
# Использование: tools/run_balance_bots.sh "1 2 3 4" [папка_проекта=source]
GODOT=${GODOT:-godot}
PROJECT=${2:-source}
OUT=${OUT:-/tmp/balance}
mkdir -p "$OUT"
for sd in $1; do
  SEED=$sd SCALE=5 DURATION=3000 timeout 1750 "$GODOT" --headless --path "$PROJECT" res://test/balance_bot.tscn > "$OUT/bot$sd.log" 2>&1 &
done
wait
grep -hE "DEAD|TIMEOUT" "$OUT"/bot*.log
