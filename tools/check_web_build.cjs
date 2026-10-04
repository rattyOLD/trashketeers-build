const { chromium, webkit } = require(process.argv[2]);
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const output = process.argv[3];
  for (const [name, type] of [['chromium', chromium], ['webkit', webkit]]) {
  const browser = await type.launch(name === 'chromium' ? {args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']} : {headless: false});
  try {
    for (const scenario of ['', '#story:m1', '#story:m2']) {
    const page = await browser.newPage({viewport: {width: 390, height: 844}, deviceScaleFactor: 1.5, isMobile: true, hasTouch: true});
    const lines = [];
    const errors = [];
    page.on('console', msg => {
      lines.push(msg.text());
      if (/SCRIPT ERROR|Parse Error|WebAssembly.*Error|memory access out of bounds/.test(msg.text())) errors.push(msg.text());
    });
    page.on('pageerror', error => errors.push(String(error)));
    await page.route('**/*', route => {
      const url = new URL(route.request().url());
      if (url.hostname === '127.0.0.1' || url.protocol === 'blob:' || url.protocol === 'data:') return route.continue();
      // No telemetry/account requests leave this isolated check. A CORS-safe stub
      // avoids WebKit's unhandled AbortError from deliberately aborted SDK scripts.
      return route.fulfill({status: 200, contentType: route.request().resourceType() === 'script' ? 'application/javascript' : 'application/json', headers: {'Access-Control-Allow-Origin': '*'}, body: '{}'});
    });
    await page.goto('http://127.0.0.1:8765/' + scenario, {waitUntil: 'domcontentloaded'});
    await page.waitForFunction(() => !document.getElementById('boot'), {timeout: 120000});
    await page.waitForTimeout(scenario ? 30000 : 8000);
    const label = name + (scenario ? '-' + scenario.slice(1).replace(':', '-') : '-menu');
    const state = await page.evaluate(() => ({trail: window.__trash_trail, crash: document.getElementById('crashlog').textContent}));
    await page.screenshot({path: path.join(output, label + '.png')});
    fs.writeFileSync(path.join(output, label + '.log'), lines.join('\n') + '\n' + JSON.stringify(state));
    if (state.crash) errors.push(state.crash);
    if (scenario && !(state.trail || []).some(line => line.includes('/Game'))) errors.push('Story did not reach Game: ' + JSON.stringify(state));
    if (errors.length) throw new Error(errors.join('\n'));
    console.log('WEB_STARTUP_OK', label);
    await page.close();
    }
  } finally {
    await browser.close();
  }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
