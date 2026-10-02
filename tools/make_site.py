import hashlib
import gzip, os, shutil, sys

scratch = os.path.dirname(os.path.abspath(__file__))
build = sys.argv[1]
site = os.path.join(scratch, "site")
os.makedirs(site, exist_ok=True)
for name in ["index.audio.worklet.js", "index.audio.position.worklet.js"]:
    shutil.copy(os.path.join(build, name), os.path.join(site, name))
# Godot 4.4 в вебе вешает на КАЖДЫЙ запуск звука отдельный AudioWorkletNode (позиция
# воспроизведения). Нам позиция не нужна, а тысячи worklet-узлов роняют iOS WebKit.
js = open(os.path.join(build, "index.js"), encoding="utf-8").read()
needle = "this._source.connect(this.getPositionWorklet());"
assert needle in js, "position worklet hook not found"
js = js.replace(needle, "")
# Шина семпла: вместо сплиттера на 6 каналов + 6 GainNode + мерджера (8 узлов на КАЖДЫЙ звук)
# один GainNode. Громкость каналов у нас одинаковая (2D-звук без панорамы).
start = js.index("SampleNodeBus:class SampleNodeBus{")
end = js.index(",sampleNodes:null", start)
js = js[:start] + ("SampleNodeBus:class SampleNodeBus{static create(bus){return new GodotAudio.SampleNodeBus(bus)}"
    "constructor(bus){this._bus=bus;this._gain=GodotAudio.ctx.createGain();this._gain.connect(this._bus.getInputNode())}"
    "getInputNode(){return this._gain}getOutputNode(){return this._gain}"
    "setVolume(volume){const l=volume[GodotAudio.GodotChannel.CHANNEL_L]??0;const r=volume[GodotAudio.GodotChannel.CHANNEL_R]??0;this._gain.gain.value=Math.max(l,r)}"
    "clear(){this._bus=null;if(this._gain){this._gain.disconnect();this._gain=null}}}") + js[end:]
open(os.path.join(site, "index.js"), "w", encoding="utf-8").write(js)
for name in os.listdir(site):
    if name.startswith(("raccoon.pack", "raccoon.core")):
        os.remove(os.path.join(site, name))


def write_parts(raw, prefix, chunk):
    parts = []
    for i in range(0, max(len(raw), 1), chunk):
        name = "%s.%d.wasm" % (prefix, i // chunk)
        data = gzip.compress(raw[i:i + chunk], 9, mtime=0)
        assert len(data) < 15 * 1024 * 1024 - 65536, name
        with open(os.path.join(site, name), "wb") as dst:
            dst.write(data)
        # Хеш содержимого в адресе: загрузчик берёт части с cache: 'force-cache', и без него браузер навсегда
        # отдавал старый пак (новая страница + старая игра). Неизменённые части по-прежнему берутся из кэша.
        digest = hashlib.sha1(data).hexdigest()[:12]
        parts.append('{url:"%s?h=%s",bytes:%d}' % (name, digest, len(data)))
    return "[" + ",".join(parts) + "]"


with open(os.path.join(build, "index.pck"), "rb") as src:
    pck_raw = src.read()
with open(os.path.join(build, "index.wasm"), "rb") as src:
    raw = src.read()
for extra in ("manifest.webmanifest", "sw.js", "icon180.png", "icon192.png", "icon512.png", "og.jpg"):
    shutil.copy("/home/claude/trashketeers-build/tools/" + extra, os.path.join(site, extra))
shutil.copy("/home/claude/raccoon/web/audio_unlock.js", os.path.join(site, "audio_unlock.js"))
shutil.copy("/home/claude/raccoon/web/render_scale.js", os.path.join(site, "render_scale.js"))
page = open("/home/claude/trashketeers-build/tools/site_template.html", encoding="utf-8").read()
import json as _json
_studio = str(_json.load(open("/home/claude/raccoon/data/brand.json")).get("studio", "")).strip()
MUG = '<img class="mug" alt="" src="data:image/webp;base64,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">'
page = page.replace("__STUDIO_LINE__", ('<p class="made">Сделано командой</p><p class="studio">' + MUG + '<span>%s</span>' % _studio + MUG + '</p>') if _studio else "")
page = page.replace("__WASM_PARTS__", write_parts(raw, "raccoon.core", 24 * 1024 * 1024))
page = page.replace("__PCK_PARTS__", write_parts(pck_raw, "raccoon.pack", 12 * 1024 * 1024))
import time
build_id = str(int(time.time()))
page = page.replace("__BUILD_ID__", build_id)
import json, subprocess, datetime
base_ver = json.load(open("/home/claude/raccoon/data/changelog.json"))["entries"][0]["version"]
try:
    number = int(subprocess.check_output(["git", "-C", "/home/claude/trashketeers-build", "rev-list", "--count", "HEAD"]).decode().strip()) + 1
except Exception:
    number = 0
build_label = "%s.%d" % (base_ver, number)
build_time = (datetime.datetime.utcnow() + datetime.timedelta(hours=7)).strftime("%d.%m %H:%M")
page = page.replace("__BUILD_LABEL__", build_label).replace("__BUILD_TIME__", build_time)
# min_build: сборки старше этой больше не запускаются (полноэкранная плашка «Обнови игру»).
# Поднимается, когда важное исправление нельзя оставить старым клиентам: FORCE_UPDATE=1 bash tools/build_main.sh
min_build = "0"
try:
    min_build = str(json.load(open("/home/claude/trashketeers-build/version.json")).get("min_build", "0"))
except Exception:
    pass
if os.environ.get("FORCE_UPDATE") == "1":
    min_build = build_id
open(os.path.join(site, "version.json"), "w").write(json.dumps({"build": build_id, "label": build_label, "time": build_time, "min_build": min_build}))
page = page.replace("__PCK_SIZE__", str(len(pck_raw)))
page = page.replace("__WASM_SIZE__", str(len(raw)))
open(os.path.join(site, "index.html"), "w", encoding="utf-8").write(page)
for name in sorted(os.listdir(site)):
    print(name, os.path.getsize(os.path.join(site, name)))
