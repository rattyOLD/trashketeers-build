# Trashketeers.io: карта проекта

Игра: топ-даун автошутер, Godot 4.4.1 (GDScript), экспорт Web (Compatibility). Тест на телефоне через GitHub Pages
(корень репозитория и `docs/` — свежая сборка). Это НЕ Telegram mini app.

## Где что лежит
- `source/` — исходники игры (открывается в Godot как проект). `tools/save_source.sh` обновляет копию.
  - `scripts/game` бой, игрок, `scripts/enemies` враги, `scripts/weapons` оружие (`melee_fighter.gd`, `weapon_vfx.gd`)
  - `scripts/biome` арены глав (`level_spawner.gd`, `arena_prop.gd`), `scripts/raid` налёт Хладгора
  - `scripts/ui` меню и HUD (`loading_screen.gd`), `data/*.json` баланс и контент
  - `data/scenes.json` — сцены расстановки пропсов; `data/chapters.json` — главы и волны, `data/weapons.json` — оружие
  - `assets/` арт (Астра), `shaders/`
- `tools/` — сборка: `sync.sh`, `build_main.sh` (импорт, проверка скриптов, smoke-тест, экспорт, `make_site.py`), `site_template.html`
  (HTML-загрузчик, пак режется на части ≤15 МБ), `slice_vfx.py` (нарезка листов Астры с удалением розового фона).
- корень и `docs/` — собранная игра для Pages (`index.html`, `raccoon.core.*.wasm`, `raccoon.pack.*.wasm`).

## Правила кода
- Только законченный код, без заглушек. Мало комментариев (только архитектурные связи).
- Строгая типизация: тернарники и типизированные массивы с явным типом; не называть переменные `seed`, `hash`, `len`.
- Пулы объектов, 60 FPS, баланс важен.

## Как собрать и выложить
1. Правки в `source/` (или в рабочей папке и `tools/save_source.sh`).
2. `tools/build_main.sh` (нужны Godot 4.4.1 и шаблоны экспорта), проверить `checked N scripts, failed 0` и отсутствие `SCRIPT ERROR`.
3. Скопировать содержимое `site/` в корень и `docs/`, коммит, `git push origin main`.

## Проверка перед выкладкой (обязательно)
- `GODOT=... tools/verify.sh` — импорт, компиляция всех скриптов (`CHECK checked N, failed 0`), бот играет выживание, сюжет, рейд и мод «враги взрываются». Выкладывать только при `VERIFY OK`.
- Веб: экспорт `Web` в `source/build/web`, затем `python3 tools/make_site.py source/build/web` → `tools/site/` → скопировать в корень и `docs/`, коммит в `main`. Номер версии берётся как следующий за `version.json`.
- Проверить загрузку сайта в Chromium (Playwright): игра должна дойти до главного меню.
- APK собирает GitHub Actions (`.github/workflows/android-beta.yml`) на каждый пуш в `source/`: подпись, Firebase App Distribution (группа `testers` + секрет `FIREBASE_TESTERS`), релиз `android-beta` с `android-version.json` для окна «ОБНОВИТЬ» в игре (`core/app_updater.gd`).

## Инструменты проверки (source/test, в сборку не попадают)
- `shot_battle` (скриншот боя: PROBE_CH, PROBE_WAVE, PROBE_Q, SHOT_AT, OUT), `boss_shot` (+BOSS=id), `map_overview` (вся карта сверху, SEED), `hud_band` (шапка телефона), `stream_test` (струи пива/рвоты), `update_popup`.
- `balance_bot` + `tools/run_balance_bots.sh` — новичок проходит выживание; ориентир баланса: смерть на волнах 5–10, босс главы — стена.
- `draw_probe`, `prof_battle`, `tools/gdprof.py` — вызовы отрисовки и профайлер GDScript.

## Телеметрия
Веб и APK шлют отчёты (perf, spike, error, run, prev_session_died с хвостом лога) в Google Apps Script → таблица. Чтение для разработки — отдельное развёртывание Apps Script с `doGet` и ключом (ключ хранится вне репозитория).

## Для Астры
Арт кладётся в `source/assets/<папка>/`. Нарезку и прозрачность делает `tools/slice_vfx.py`.
Требования к арту — в `astra/from_claude/BRIEF_v32_all_needs.md`.
