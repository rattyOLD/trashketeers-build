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
        parts.append('{url:"%s",bytes:%d}' % (name, len(data)))
    return "[" + ",".join(parts) + "]"


with open(os.path.join(build, "index.pck"), "rb") as src:
    pck_raw = src.read()
with open(os.path.join(build, "index.wasm"), "rb") as src:
    raw = src.read()
shutil.copy("/home/claude/raccoon/web/audio_unlock.js", os.path.join(site, "audio_unlock.js"))
shutil.copy("/home/claude/raccoon/web/render_scale.js", os.path.join(site, "render_scale.js"))
page = open(os.path.join(scratch, "site_template.html"), encoding="utf-8").read()
page = page.replace("__WASM_PARTS__", write_parts(raw, "raccoon.core", 24 * 1024 * 1024))
page = page.replace("__PCK_PARTS__", write_parts(pck_raw, "raccoon.pack", 12 * 1024 * 1024))
import time
build_id = str(int(time.time()))
page = page.replace("__BUILD_ID__", build_id)
open(os.path.join(site, "version.json"), "w").write('{"build":"%s"}' % build_id)
page = page.replace("__PCK_SIZE__", str(len(pck_raw)))
page = page.replace("__WASM_SIZE__", str(len(raw)))
open(os.path.join(site, "index.html"), "w", encoding="utf-8").write(page)
for name in sorted(os.listdir(site)):
    print(name, os.path.getsize(os.path.join(site, name)))
