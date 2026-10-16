#!/usr/bin/env python3
"""Real browser checks for the landscape host and transformed-frame touch input."""
import asyncio
import functools
import json
import tempfile
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]

class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

INIT = '''
window.__qaOrientation = 'portrait-primary';
try {Object.defineProperty(window,'orientation',{get:()=>top.__qaOrientation.startsWith('portrait')?0:90});} catch(e) {}
Object.defineProperty(screen,'orientation',{value:{get type(){return top.__qaOrientation},lock:()=>Promise.reject(new Error('NotSupportedError'))}});
Element.prototype.requestFullscreen=undefined; Element.prototype.webkitRequestFullscreen=undefined;
'''

async def check(browser, base, name):
    context = await browser.new_context(viewport={'width':390,'height':844},screen={'width':390,'height':844},is_mobile=True,has_touch=True,device_scale_factor=2)
    await context.add_init_script(INIT)
    page = await context.new_page()
    errors = []
    page.on('pageerror',lambda error:errors.append(str(error)))
    await page.goto(base+'/?dev=fixture#story:m1')
    await page.wait_for_function("!document.getElementById('boot')")
    game = page.frames[1]
    assert await page.evaluate("document.documentElement.dataset.gameRotation") == '90'
    assert await game.evaluate('innerWidth > innerHeight')
    assert not await game.locator('#rotate').count()
    assert await game.evaluate('!!window.__trashHost && !window.__trashHost.supported()')
    async def physical(u,v):
        rectangle = await page.locator('#game-frame').bounding_box()
        rotated = await page.evaluate("document.documentElement.dataset.gameRotation==='90'")
        return {'x':rectangle['x']+rectangle['width']-v,'y':rectangle['y']+u} if rotated else {'x':rectangle['x']+u,'y':rectangle['y']+v}
    async def tap_and_check(u,v):
        await page.evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))')
        await game.wait_for_function('innerWidth === frameElement.clientWidth && innerHeight === frameElement.clientHeight')
        count=await game.evaluate("events.filter(e=>e.kind==='touchstart').length")
        point = await physical(u,v)
        await page.touchscreen.tap(point['x'],point['y'])
        await game.wait_for_function("(count)=>events.filter(e=>e.kind==='touchstart').length>count",arg=count,timeout=5000)
        last = await game.evaluate("events.filter(e=>e.kind==='touchstart').at(-1).points[0]")
        assert abs(last['x']-u)<2 and abs(last['y']-v)<2,(name,last,u,v)
    await tap_and_check(150,300)
    if name == 'chromium':
        session = await context.new_cdp_session(page)
        points = [await physical(120,310),await physical(700,305)]
        await session.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{**point,'id':i+5} for i,point in enumerate(points)]})
        started = await game.evaluate("events.filter(e=>e.kind==='touchstart').at(-1).active")
        assert len(started)==2 and len({point['id'] for point in started})==2
        for point,target in zip(started,[(120,310),(700,305)]):
            assert abs(point['x']-target[0])<2 and abs(point['y']-target[1])<2
        moved = [await physical(160,315),await physical(660,300)]
        await session.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{**point,'id':i+5} for i,point in enumerate(moved)]})
        latest = await game.evaluate("events.filter(e=>e.kind==='touchmove').at(-1).active")
        assert len(latest)==2
        for point,target in zip(latest,[(160,315),(660,300)]):
            assert abs(point['x']-target[0])<2 and abs(point['y']-target[1])<2
        await session.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
        await session.detach()
    box = await game.locator('#name').bounding_box()
    # Locator bounding boxes are already in top-level screen coordinates.
    await page.touchscreen.tap(box['x']+box['width']/2,box['y']+box['height']/2)
    assert await game.evaluate("document.activeElement.id==='name'")
    await page.keyboard.type('tester42')
    assert await game.locator('#name').input_value() == 'tester42'
    # Android can shrink the visual/layout viewport for a keyboard without a
    # physical rotation. Preserve landscape and the same input/document.
    await page.set_viewport_size({'width':390,'height':350})
    await page.wait_for_function("document.documentElement.dataset.gameRotation==='90'")
    await game.wait_for_function('innerWidth===350 && innerHeight===390')
    assert await game.locator('#name').input_value() == 'tester42'
    await page.set_viewport_size({'width':390,'height':844})
    await game.wait_for_function('innerWidth===844 && innerHeight===390')
    await page.evaluate("window.__qaOrientation='landscape-primary'")
    await page.set_viewport_size({'width':844,'height':390})
    await page.wait_for_function("document.documentElement.dataset.gameRotation==='0'")
    assert await game.locator('#name').input_value() == 'tester42'
    await game.locator('#name').blur()
    await tap_and_check(120,300)
    await page.evaluate("window.__qaOrientation='portrait-primary'")
    await page.set_viewport_size({'width':390,'height':844})
    await page.wait_for_function("document.documentElement.dataset.gameRotation==='90'")
    assert await game.locator('#name').input_value() == 'tester42'
    await tap_and_check(180,305)
    # Reserve the physical notch/home-indicator margins before rotating the frame.
    await page.locator('#viewport-probe').evaluate("el=>el.style.padding='20px 10px 30px 5px'")
    await page.evaluate('trashLandscapeHost.fit()')
    await game.wait_for_function('innerWidth===794 && innerHeight===375')
    await tap_and_check(180,300)
    await page.locator('#viewport-probe').evaluate("el=>el.style.padding=''")
    await page.evaluate('trashLandscapeHost.fit()')
    await game.wait_for_function('innerWidth===844 && innerHeight===390')
    await game.evaluate("history.replaceState(null,'','game.html?dev=fixture&_build=fixture#story:m2')")
    assert '_build=' not in page.url and page.url.endswith('?dev=fixture#story:m2')
    assert await game.evaluate("window.__trashHost.canonical()") == base+'/'
    await page.evaluate("window.__installs=0;var event=new Event('beforeinstallprompt',{cancelable:true});event.prompt=()=>{window.__installs++};dispatchEvent(event)")
    assert await game.evaluate('window.__trashHost.canInstall()')
    assert await game.evaluate('window.__trashHost.install()')
    assert not await game.evaluate('window.__trashHost.canInstall()')
    assert await page.evaluate('window.__installs') == 1
    await game.evaluate("window.__trashHost.setManifest({name:'QA',start_url:window.__trashHost.path(),scope:'/'})")
    manifest = await page.evaluate("fetch(document.querySelector('link[rel=manifest]').href).then(r=>r.json())")
    assert manifest['start_url']=='/'
    assert not errors,errors
    await context.close()
    # A supported API can still reject fullscreen. That must never block input.
    context = await browser.new_context(viewport={'width':390,'height':844},is_mobile=True,has_touch=True)
    await context.add_init_script(INIT+"Element.prototype.requestFullscreen=function(){return Promise.reject(new Error('NotAllowedError'))};")
    page = await context.new_page();errors=[]
    page.on('pageerror',lambda error:errors.append(str(error)))
    await page.goto(base+'/')
    await page.wait_for_function("!document.getElementById('boot')")
    game=page.frames[1]
    await page.touchscreen.tap(60,140)
    await page.wait_for_timeout(250)
    assert await game.evaluate("events.some(e=>e.kind==='touchstart')")
    assert await page.evaluate("document.documentElement.dataset.gameRotation")=='90'
    assert not errors,errors
    await context.close()
    # A desktop viewport must not be rotated or request fullscreen on a click.
    context=await browser.new_context(viewport={'width':1280,'height':720})
    page=await context.new_page()
    await page.goto(base+'/')
    await page.wait_for_function("!document.getElementById('boot')")
    game=page.frames[1]
    assert await page.evaluate("document.documentElement.dataset.gameRotation")=='0'
    assert await game.evaluate('innerWidth===1280 && innerHeight===720')
    await page.mouse.click(100,100)
    assert not await page.evaluate('trashLandscapeHost.isFullscreen()')
    await context.close()
    print('LANDSCAPE_OK',name,'rotation, trusted input, orientation changes, keyboard, links, PWA, API rejection, safe area, desktop',flush=True)

async def main():
    with tempfile.TemporaryDirectory(prefix='trash-landscape-') as temporary:
        folder=Path(temporary)
        metadata='<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="manifest" href="manifest.webmanifest"><title>QA</title>'
        host=(ROOT/'tools/landscape_host.html').read_text().replace('__PAGE_METADATA__',metadata).replace('__BUILD_ID__','fixture')
        (folder/'index.html').write_text(host)
        (folder/'landscape_bridge.js').write_text((ROOT/'tools/landscape_bridge.js').read_text())
        (folder/'game.html').write_text('''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;touch-action:none}canvas{position:fixed;inset:0;width:100%;height:100%;touch-action:none}input{position:absolute;left:40%;top:35%;width:20%;height:24px}</style><body><div id="boot"></div><canvas id="canvas" tabindex="0"></canvas><input id="name"><script src="landscape_bridge.js"></script><script>window.events=[];for(const kind of ['touchstart','touchmove','touchend'])addEventListener(kind,e=>{events.push({kind,points:Array.from(e.changedTouches).map(t=>({x:t.clientX,y:t.clientY,id:t.identifier})),active:Array.from(e.touches).map(t=>({x:t.clientX,y:t.clientY,id:t.identifier}))});},{passive:false});setTimeout(()=>document.getElementById('boot').remove(),100);</script>''')
        (folder/'manifest.webmanifest').write_text('{"name":"QA","start_url":"./"}')
        server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(QuietHandler,directory=str(folder)))
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            async with async_playwright() as playwright:
                for name in ['chromium','webkit']:
                    browser=await getattr(playwright,name).launch(args=['--no-sandbox'] if name=='chromium' else [])
                    try:await check(browser,'http://127.0.0.1:'+str(server.server_port),name)
                    finally:await browser.close()
        finally:server.shutdown();server.server_close()
    print('LANDSCAPE_CHECK_OK',flush=True)

if __name__=='__main__':
    asyncio.run(main())
