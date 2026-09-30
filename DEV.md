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

## Для Астры
Арт кладётся в `source/assets/<папка>/`. Нарезку и прозрачность делает `tools/slice_vfx.py`.
Промпты и требования — в проектных документах Claude Project «AppRaccoon» (`astra_brief.md`).
