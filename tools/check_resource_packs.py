"""Exercise resource-pack queue, shared requests and retry with real browser promises."""
import asyncio,json
from pathlib import Path
from playwright.async_api import async_playwright
SCRIPT=(Path(__file__).parent/'resource_packs.js').read_text()
async def main():
 async with async_playwright() as p:
  for name in ['chromium','webkit']:
   browser=await getattr(p,name).launch(args=['--no-sandbox'] if name=='chromium' else [])
   page=await browser.new_page()
   result=await page.evaluate('''async source=>{
    const FILES={},loadedParts={},loaded={},calls={},copied=[];
    let active=0,peak=0,broken=true;
    const check=(v,msg)=>{if(!v)throw Error(msg)};
    async function download(key){
     calls[key]=(calls[key]||0)+1;active++;peak=Math.max(active,peak);
     await new Promise(r=>setTimeout(r,10));active--;
     if(key==='bundle:failed'&&broken)throw Error('network failure');
     return new Uint8Array([1,2,3]);
    }
    const manifest={groups:{a:{parts:[{bytes:3}]},b:{parts:[{bytes:3}]},failed:{parts:[{bytes:3}]}},resources:{'res://a':'a'},enemies:{rat:['a','b']}};
    const install=eval('('+source.replace(/^\\/\\/[^\\n]*\\n/,'').trim()+')');
    const bridge=install(manifest,()=>({copyToFS(path,bytes){check(String(bytes)==='1,2,3','bytes changed');copied.push(path)}}));
    const wait=async id=>{for(let i=0;i<100;i++){const s=bridge.status(id);if(s.state!=='loading')return s;await new Promise(r=>setTimeout(r,10))}throw Error('ticket stuck')};
    const first=bridge.start(['a','b','a']),second=bridge.start(['a']);
    const results=await Promise.all([wait(first),wait(second)]);
    check(results.every(x=>x.state==='ready'),'shared ticket failed');
    check(calls['bundle:a']===1&&calls['bundle:b']===1&&peak===1,'duplicate or parallel pack');
    check(results[0].files.length===2&&copied.length===2,'mount files');
    check(bridge.resources['res://a']==='a'&&String(bridge.enemyGroups(['rat','rat']))==='a,b','manifest lookup');
    check((await wait(bridge.start(['failed']))).state==='error','network failure hidden');
    broken=false;check((await wait(bridge.start(['failed']))).state==='ready','retry failed');
    check(calls['bundle:failed']===2,'failure cached permanently');
    return {peakPacks:peak,sharedRequests:true,retry:true,bytesExact:true};
   }''',SCRIPT)
   print('RESOURCE_PACKS_OK',name,json.dumps(result),flush=True)
   await browser.close()
asyncio.run(main())
