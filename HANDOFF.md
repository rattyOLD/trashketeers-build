# TrashSquad — передача работы (Beer Party Studio)

Для Claude, который продолжит проект. Правила владельца: см. `CLAUDE.md` (оптимизация в приоритете; графику/механику не менять без спроса; APK всегда «TrashSquad»; упоминать Beer Party Studio; без строк Co-Authored-By/Claude-Session в коммитах).

## Где что
- Код игры: `source/` (Godot 4.4.1, GDScript, Compatibility). Ветки: `main` = живой веб (GitHub Pages) + APK; `perf/draw-batching` = рабочая, держать равной `main`.
- Выкладка веба и проверки: `DEV.md` → «Проверка перед выкладкой». Коротко: `tools/verify.sh` (ноль SCRIPT ERROR), экспорт Web, `python3 tools/make_site.py <build/web>`, `tools/site/*` → корень и `docs/`, коммит в `main`.
- APK: `.github/workflows/android-beta.yml` на каждый пуш в `source/` → подпись → Firebase App Distribution (группа `testers`, секрет `FIREBASE_TESTERS` — почты) → релиз `android-beta` на GitHub (`android-version.json`) → в игре окно «ОБНОВИТЬ» (`source/scripts/core/app_updater.gd`).
- Телеметрия (веб+APK → Google Apps Script → таблица): чтение журнала — отдельное развёртывание Apps Script с `doGet?key=...` (ссылка и ключ у владельца). APK шлёт модель, GPU, память и хвост лога перед вылетом (`core/native_telemetry.gd`).

## Что сделано (октябрь 2026)
- Отрисовка: PolyBatch (`fx/poly_batch.gd`) — вызовов отрисовки в бою в 4–6 раз меньше; карта освещения `game/light_map.gd` (1/4 разрешения, виньетка, полутень, свет по главам).
- Память/вылеты: `core/battle_memory.gd` чистит кэши при выходе из боя; очередь цепных взрывов в `combat/bullet_pool.gd` (Maximum call stack); прогрев текстур главы (`Game.warm_chapter`) и шрифтов (`BattleBase._warm_glyphs`); APK рендерит 720×1280 на качестве 0–1 (`Platform.set_render_cap`).
- Интерфейс: шапка ≤22.5% экрана, очередь строки событий, компактная полоса босса; навык и стволы справа внизу под большим пальцем.
- Геймплей: рывок удалён, у Рико навык «Шквал»; баланс (`data/chapters.json` → difficulty: early_*, mini_hp, рост по волнам), бот `test/balance_bot` — новичок умирает на волнах 5–10.
- Импакт: хитмаркеры (едут за мобом), подтверждение убийства, выкрики серий, звуки выстрелов с низами.
- Карты выживания: +50%, 9 районов со своей темой (`biome/level_spawner.gd` → `_build_districts`), бордюры, лужи у обочин.
- Струи пива/рвоты лентой (`FxManager._draw_liquid_streams`).

## Открытые задачи (по приоритету)
1. Вылеты/нагрев: читать журнал (kinds: prev_session_died, unclean_exit, spike, perf, adapt) — в APK есть хвост лога перед смертью.
2. Артефакты на карте (жалоба владельца, без скриншота): проверить `light_map.gd` (полутень `_mottle_rect`, стыки при движении камеры), бордюры `ArenaDecor.Curbs`, лужи `ArenaDecor.Puddles`, `ShadowDecals`. Попросить скриншот.
3. Сюжет: перерисовать карты сюжета (map design) и сделать интереснее; вылет при входе в сюжет на iPhone был по памяти — исправлено, проверить по журналу.
4. Арт от Астры (задание у владельца): Мася (кот, сейчас фото), струи боссов, фон районов со зрителями-крысами/свиньями (по главе), — встроить, зрители реагируют на бой.
5. Ошибка «Lambda capture freed» — отложенные таймеры старого боя после выхода (безвредно, но шумит).
6. iOS TestFlight — когда владелец даст данные Apple.
7. Обновление APK целиком внутри игры (без браузера): перевести экспорт Android на Gradle-сборку (`gradle_build/use_gradle_build=true`, шаблон android_source), написать Android-плагин v2 (Kotlin): скачать APK в cacheDir с прогрессом → FileProvider → Intent ACTION_VIEW (application/vnd.android.package-archive) + разрешение REQUEST_INSTALL_PACKAGES; в `core/app_updater.gd` вместо `OS.shell_open` — загрузка HTTPRequest в user:// с полоской и вызов плагина. Проверить на Android 8–14.
8. Тестер-меню теперь открыто и Insider (`MainMenuUI._sync_tester_button`): проверить, что из него нельзя добыть монеты/прокачку, иначе закрыть такие пункты для Insider.
