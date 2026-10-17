# Подготовка банка v38

Работать из корня репозитория. Нужны Node18+, Blender4.3 и Python с Pillow/numpy для проверки. Временные каталоги находятся вне репозитория. У Blender код возврата не всегда отражает ошибку Python: проверять `model_report.json`, лог и контракт GLB.

```bash
node tools/art_v38/prepare_bank_textures.mjs astra/previews/v38/bank_materials_source.png astra/previews/v38/bank_trim_source.png astra/previews/v38/bank_approved_elevation.png /tmp/bank38-textures
blender -b -t 4 --python tools/art_v38/build_bank.py -- /tmp/bank38-model /tmp/bank38-textures --day-only
python tools/art_v38/pack_glb.py /tmp/bank38-model/bank_hall.gltf /tmp/bank38-delivery
node tools/art_v38/optimize_png.mjs /tmp/bank38-delivery/*.png
python tools/art_v38/validate_bank.py /tmp/bank38-delivery
```

`--no-render` вместо `--day-only` экспортирует только модель. Без этих ключей Blender снимает также поворот и вечер. GLB содержит бинарную геометрию и внешние URI PNG; отдельные glTF/bin — промежуточные файлы, не сдача. Сжатие PNG меняет только IDAT и проверяет побайтное совпадение декодированных RGBA.

`qa_bank.py` создаёт отдельный минимальный Godot-проект с **реальным GLB**, принятым Рико и брусчаткой. `check_bank_render.py` проверяет кадры/лог и отличия нормалей. `package_bank.py` собирает inbox и manifest. Инструменты не редактируют рабочий `source/` и не настраивают атмосферу настоящей площади.

Макропрофили нормалей авторские приближённые. Палитра стекла приглушена относительно исходной яркой синевы; остальные материалы сохраняют свои оттенки. Геометрия не строится из плоского фасада на коробке: проёмы вырезаны, колонны/карнизы/скаты имеют объём, герб и плющ — отдельные детали.

TrashSquad · Beer Party Studio.
