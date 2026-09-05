// Headless render of each pet state → web/shots/<state>.png (uses the Playwright install from ~/dx-machine)
const { chromium } = require('/Users/dmitrypyanov/dx-machine/node_modules/playwright')
const path = require('path')
;(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] })
  const page = await browser.newPage({ viewport: { width: 320, height: 320 }, deviceScaleFactor: 2 })
  page.on('pageerror', e => console.log('PAGE ERROR', e.message))
  page.on('console', m => { if (m.type() === 'error') console.log('CONSOLE', m.text()) })
  const file = 'file://' + path.resolve(__dirname, '../dist-preview/index.html')
  for (const s of ['idle', 'listening', 'thinking', 'done', 'noting', 'confused', 'sleeping']) {
    await page.goto(`${file}?bg=1&state=${s}`)
    await page.waitForTimeout(s === 'done' ? 350 : 900)
    await page.screenshot({ path: path.resolve(__dirname, `../shots/${s}.png`) })
    console.log('shot', s)
  }
  await browser.close()
})().catch(e => { console.error(e); process.exit(1) })
