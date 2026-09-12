// Headless render of each pet state to web/shots/<state>.png.
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { launchBrowser } from './browser.js'

const toolDir = path.dirname(fileURLToPath(import.meta.url))

async function main() {
  const browser = await launchBrowser({
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  })
  const page = await browser.newPage({ viewport: { width: 320, height: 320 }, deviceScaleFactor: 2 })
  page.on('pageerror', error => console.log('PAGE ERROR', error.message))
  page.on('console', message => {
    if (message.type() === 'error') console.log('CONSOLE', message.text())
  })

  const file = `file://${path.resolve(toolDir, '../dist-preview/index.html')}`
  for (const state of ['idle', 'listening', 'thinking', 'done', 'noting', 'confused', 'sleeping']) {
    await page.goto(`${file}?bg=1&state=${state}`)
    await page.waitForTimeout(state === 'done' ? 350 : 900)
    await page.screenshot({ path: path.resolve(toolDir, `../shots/${state}.png`) })
    console.log('shot', state)
  }
  await browser.close()
}

main().catch(error => {
  console.error(error)
  process.exitCode = 1
})
