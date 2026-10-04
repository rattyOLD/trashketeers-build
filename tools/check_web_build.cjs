const { chromium } = require(process.argv[2]);
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const output = process.argv[3];
  const browser = await chromium.launch({args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
  try {
    const page = await browser.newPage({viewport: {width: 720, height: 1280}});
    const lines = [];
    const errors = [];
    page.on('console', msg => {
      lines.push(msg.text());
      if (/SCRIPT ERROR|Parse Error|WebAssembly.*Error|memory access out of bounds/.test(msg.text())) errors.push(msg.text());
    });
    page.on('pageerror', error => errors.push(String(error)));
    await page.route('**/*', route => new URL(route.request().url()).hostname === '127.0.0.1' ? route.continue() : route.abort());
    await page.goto('http://127.0.0.1:8765', {waitUntil: 'domcontentloaded'});
    await page.waitForFunction(() => !document.getElementById('boot'), {timeout: 120000});
    await page.waitForTimeout(8000);
    await page.screenshot({path: path.join(output, 'web-startup.png')});
    fs.writeFileSync(path.join(output, 'web-console.log'), lines.join('\n'));
    if (errors.length) throw new Error(errors.join('\n'));
    console.log('WEB_STARTUP_OK');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
