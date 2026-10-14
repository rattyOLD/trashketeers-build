"""Verify persistent binary caching, obsolete-version pruning and storage-denied fallback."""
import asyncio,json,os
from pathlib import Path
from playwright.async_api import async_playwright
source=(Path(__file__).parent/'asset_cache.js').read_text()
async def main():
 async with async_playwright() as p:
  for name in ['chromium','webkit']:
   browser=await getattr(p,name).launch(args=['--no-sandbox'] if name=='chromium' else [])
   page=await browser.new_page();await page.goto(os.environ.get('WEB_TEST_URL','http://127.0.0.1:8768')+'/render_scale.js')
   await page.evaluate('async()=>{for(const key of await caches.keys())if(key.startsWith("trash-squad-packs-v1:"))await caches.delete(key)}')
   result=await page.evaluate('''async source=>{
    const install=eval('('+source.replace(/^\\/\\/[^\\n]*\\n/,'').trim()+')');
    const check=(v,msg)=>{if(!v)throw Error(msg)};
    let cache=install(['pack.wasm?h=1','obsolete.wasm?h=0']);
    check(!await cache.read('pack.wasm?h=1'),'cold cache not empty');
    await cache.write('pack.wasm?h=1',new Uint8Array([31,139,1,2,3]));
    await cache.write('obsolete.wasm?h=0',new Uint8Array([4]));
    cache=install(['pack.wasm?h=1']);
    const response=await cache.read('pack.wasm?h=1');
    check(response&&String(new Uint8Array(await response.arrayBuffer()))==='31,139,1,2,3','compressed bytes changed');
    check(!await cache.read('obsolete.wasm?h=0'),'obsolete asset retained');
    await cache.drop('pack.wasm?h=1');check(!await cache.read('pack.wasm?h=1'),'corrupt entry not dropped');
    Object.defineProperty(window,'caches',{configurable:true,value:{open:async()=>{throw Error('storage denied')}}});
    cache=install(['pack.wasm?h=1']);check(!await cache.read('pack.wasm?h=1'),'storage rejection surfaced');
    await cache.write('pack.wasm?h=1',new Uint8Array([1]));await cache.drop('pack.wasm?h=1');
    return {exactBytes:true,pruned:true,drop:true,deniedFallback:true};
   }''',source)
   print('ASSET_CACHE_OK',name,json.dumps(result),flush=True);await browser.close()
asyncio.run(main())
