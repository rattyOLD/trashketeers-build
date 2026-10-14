"""Check emitted web loader and audio memory behavior with Playwright browsers.

Run after make_site.py, with PLAYWRIGHT_BROWSERS_PATH pointing to installed browsers.
Serve tools/site on 127.0.0.1:8765 before running.
"""
import asyncio, json, os, gzip
from pathlib import Path
from playwright.async_api import async_playwright
root=Path(__file__).resolve().parent.parent
js=(root/'tools/site/index.js').read_text()
a=js.index('Sample:class Sample{');b=js.index(',SampleNodeBus:',a)
sample=js[a+7:b]
html=(root/'tools/site_template.html').read_text();a=html.index('\tfunction download(key) {');b=html.index('\n\t// Хост',a)
loader=html[a:b]
a=html.index('\tfunction gunzipIfNeeded(bytes) {');b=html.index('\n\t// Мост',a)
gunzip=html[a:b]
async def main():
 async with async_playwright() as p:
  for kind in ['webkit','chromium']:
   browser=await getattr(p,kind).launch(args=['--no-sandbox'] if kind=='chromium' else [])
   page=await browser.new_page()
   await page.goto(os.environ.get('WEB_TEST_URL', 'http://127.0.0.1:8765') + '/render_scale.js')
   await page.add_script_tag(url=os.environ.get('WEB_TEST_URL', 'http://127.0.0.1:8765') + '/pako_inflate.min.js')
   result=await page.evaluate('''async ([sampleSource,loaderSource,gunzipSource,compressed])=>{
    const check=(ok,msg)=>{if(!ok)throw Error(msg)};
    const inflate=eval('('+gunzipSource.trim()+')');
    const native=window.DecompressionStream;
    const expected='TrashSquad · Beer Party Studio. 🦝';
    check(new TextDecoder().decode(await inflate(new Uint8Array(compressed)))===expected,'native gzip changed bytes');
    window.DecompressionStream=undefined;
    check(new TextDecoder().decode(await inflate(new Uint8Array(compressed)))===expected,'local pako fallback failed');
    window.DecompressionStream=native;
    const ctx=new OfflineAudioContext(2,128,48000);
    const GodotAudio={ctx,samples:new Map()};
    GodotAudio.Sample=eval('('+sampleSource+')');
    const pcm=ctx.createBuffer(2,128,48000);
    pcm.getChannelData(0).fill(.2);pcm.getChannelData(1).fill(.3);
    const sample=GodotAudio.Sample.create({id:'test',audioBuffer:pcm});
    for(let i=0;i<1000;i++)check(sample.getAudioBuffer()===pcm,'PCM cloned');
    const one=ctx.createBufferSource(),two=ctx.createBufferSource();
    one.buffer=sample.getAudioBuffer();two.buffer=sample.getAudioBuffer();
    one.playbackRate.value=.5;two.playbackRate.value=1.5;
    const gain=ctx.createGain();gain.gain.value=.5;
    one.connect(ctx.destination);two.connect(gain);gain.connect(ctx.destination);
    one.start();two.start();one.stop(64/48000);
    check(one.playbackRate.value===.5&&two.playbackRate.value===1.5,'pitch coupled');
    const mixed=await ctx.startRendering();
    check(Math.abs(mixed.getChannelData(0)[16]-.3)<.0001,'overlapping voices');
    check(Math.abs(mixed.getChannelData(0)[70]-.1)<.0001,'stop affected another voice');
    check(Math.abs(mixed.getChannelData(1)[70]-.15)<.0001,'stereo/volume changed');
    const mono=ctx.createBuffer(1,64,48000);mono.getChannelData(0).fill(.4);
    const fallback=GodotAudio.Sample.create({id:'mono',audioBuffer:mono});
    const normalized=fallback.getAudioBuffer();
    check(normalized.numberOfChannels===2&&normalized===fallback.getAudioBuffer(),'normalization not cached');
    check(normalized.getChannelData(0)[0]===mono.getChannelData(0)[0],'normalization changed PCM');
    fallback.setAudioBuffer(pcm);check(fallback.getAudioBuffer()===pcm,'stale normalized PCM');
    sample.clear();let cleared=false;try{sample.getAudioBuffer()}catch(e){cleared=true}check(cleared&&!GodotAudio.samples.has('test'),'clear retains sample');
    const FILES={pack:{parts:[{rawBytes:3,url:'a'},{rawBytes:2,url:'b'},{rawBytes:4,url:'c'}]}};
    const pieces=[new Uint8Array([1,2,3]),new Uint8Array([4,5]),new Uint8Array([6,7,8,9])];
    let active=0,peak=0;
    async function downloadPart(key,i){active++;peak=Math.max(active,peak);await new Promise(r=>setTimeout(r,[30,5,10][i]));active--;return pieces[i]}
    const download=eval('('+loaderSource.trim()+')');
    check(String(await download('pack'))==='1,2,3,4,5,6,7,8,9','out-of-order pack');
    check(peak===2,'unbounded pack workers');
    FILES.single={parts:[{rawBytes:3,url:'single'}]};
    check(String(await download('single'))==='1,2,3','single part altered');
    FILES.single.parts[0].rawBytes=4;let singleRejected=false;try{await download('single')}catch(e){singleRejected=true}check(singleRejected,'wrong single-part size accepted');
    FILES.pack.parts[1].rawBytes=3;let rejected=false;try{await download('pack')}catch(e){rejected=true}check(rejected,'wrong part size accepted');
    return {pcmReuses:1000,stereo:true,independentVoices:true,loaderWorkers:peak,sizeRejected:true,localPako:true};
   }''',[sample,loader,gunzip,list(gzip.compress('TrashSquad · Beer Party Studio. 🦝'.encode(),mtime=0))])
   print('WEB_MEMORY_CONTRACT_OK',kind,json.dumps(result),flush=True)
   await browser.close()
asyncio.run(main())
