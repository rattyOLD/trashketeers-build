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
MUG = (
    '<svg class="mug" viewBox="0 0 64 64" width="34" height="34" aria-hidden="true">'
    '<path d="M14 24h30v28a6 6 0 0 1-6 6H20a6 6 0 0 1-6-6z" fill="#ffb020" stroke="#1a0033" stroke-width="3"/>'
    '<path d="M44 30h6a6 6 0 0 1 0 14h-6" fill="none" stroke="#1a0033" stroke-width="3"/>'
    '<path d="M44 30h6a6 6 0 0 1 0 14h-6" fill="none" stroke="#c3bfd8" stroke-width="1.2"/>'
    '<circle cx="19" cy="22" r="7" fill="#fff6dc" stroke="#1a0033" stroke-width="2.5"/>'
    '<circle cx="29" cy="18" r="8" fill="#fff6dc" stroke="#1a0033" stroke-width="2.5"/>'
    '<circle cx="39" cy="22" r="7" fill="#fff6dc" stroke="#1a0033" stroke-width="2.5"/>'
    '<path d="M16 28l-1-9 8 4zM42 28l1-9-8 4z" fill="#5a5470" stroke="#1a0033" stroke-width="2"/>'
    '<rect x="17" y="36" width="24" height="9" rx="4.5" fill="#1a0033"/>'
    '<circle cx="24" cy="40.5" r="2.4" fill="#fff"/><circle cx="34" cy="40.5" r="2.4" fill="#fff"/>'
    '<ellipse cx="29" cy="47" rx="3" ry="2" fill="#1a0033"/></svg>'
)
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
open(os.path.join(site, "version.json"), "w").write('{"build":"%s","label":"%s","time":"%s"}' % (build_id, build_label, build_time))
page = page.replace("__PCK_SIZE__", str(len(pck_raw)))
page = page.replace("__WASM_SIZE__", str(len(raw)))
open(os.path.join(site, "index.html"), "w", encoding="utf-8").write(page)
for name in sorted(os.listdir(site)):
    print(name, os.path.getsize(os.path.join(site, name)))
