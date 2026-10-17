# Подготовка банка v38, редакция детализации

Из корня репозитория, Node18+, Blender4.3, Python с Pillow/numpy. Промежуточные файлы — вне репозитория. У Blender код возврата не всегда отражает ошибку Python: проверять model_report, лог и контракт GLB.

```bash
node tools/art_v38/prepare_bank_textures.mjs astra/previews/v38/bank_materials_detail_source.png astra/previews/v38/bank_trim_source.png astra/previews/v38/bank_approved_elevation.png /tmp/bank38-textures astra/previews/v38/bank_cutouts_detail_source.png
blender -b -t 4 --python tools/art_v38/build_bank.py -- /tmp/bank38-model /tmp/bank38-textures --day-only
python tools/art_v38/pack_glb.py /tmp/bank38-model/bank_hall.gltf /tmp/bank38-delivery
node tools/art_v38/optimize_png.mjs /tmp/bank38-delivery/*.png
cp /tmp/bank38-textures/bank_palette.png /tmp/bank38-delivery/bank_palette.png
python tools/art_v38/validate_bank.py /tmp/bank38-delivery
```

Подготовка также читает `astra/previews/v38/bank_glass_reflection_reference.png`: это сохранённая принятая текстура отражений первой редакции. Материалы и изолированный герб/плющ — новые концептные основы. Экспорт: медианные пробы на целевой сетке, ограниченные рампы, общая палитра 128, очистка связанных компонентов маски, тёмный контур. Старые цветные края исходных больших иллюстраций не проходят в итоговые PNG. Предпросмотр этих исходников не заменяет итоговую текстуру из inbox.

`--no-render` экспортирует только геометрию. Без ключей Blender снимает ещё поворот и вечер. Геометрия — настоящие проёмы, колонны, рельеф, низкая крыша за парапетом, объёмные балясины и ступени. Плотность UV задаётся метрически, внешние PNG сохраняются рядом с GLB. Скрытые грани деталей, полностью лежащие в других непрозрачных объёмах, удаляются до экспорта; контур балясин сохранён.

`qa_bank.py` создаёт отдельный Godot-проект с реальным GLB, принятыми Рико и брусчаткой. В QA импортировать PNG без потерь (`compress/mode=0`, `detect_3d/compress_to=0`, `roughness/mode=1`). `check_bank_render.py` проверяет четыре кадра и лог; `package_bank.py` собирает inbox и manifest. PNG сжимаются без изменения декодированных пикселей. Макронормали приближённые, OpenGL+Y. Проверка не изменяет рабочий source/ и не подменяет показ модели в полной площади.

TrashSquad · Beer Party Studio.

## Первая партия персонажей — щитовик

```bash
node tools/art_v38/prepare_pig_guard.mjs astra/previews/v38/pig_guard_source.png /tmp/guard38
python tools/art_v38/deliver_pig_guard.py /tmp/guard38
python tools/art_v38/validate_pig_guard.py astra/inbox/hd2d_test/chars
python tools/art_v38/qa_pig_guard.py /tmp/guard38 /tmp/guard38-plaza
```

Дальше импорт/запуск отдельного Godot-проекта через Compatibility; лог runtime сохранить как render.log. `check_pig_guard_render.py` сверяет кадры, нормаль/тень и совпадение декодированных пикселей с inbox после сжатия PNG. `prepare_rico96.cleanup` теперь принимает необязательные coreHeight/sourceAlpha; значения по умолчанию прежние. Принятый экспорт Рико повторён с теми же SHA. Собственная палитра щитовика не заменяет chars.png Рико. Общий manifest содержит раздельные данные персонажей.
