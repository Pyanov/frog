// Renders a scripted performance of the pet to PNG frames with a deterministic clock.
// node tools/video.cjs timeline.json outdir
const { chromium } = require('/Users/dmitrypyanov/dx-machine/node_modules/playwright')
const path = require('path'), fs = require('fs')
const [,, timelinePath, outDir, probeArg] = process.argv
const probe = probeArg ? probeArg.split(',').map(Number) : null
const tl = JSON.parse(fs.readFileSync(timelinePath, 'utf8'))
const FPS = 30, SIZE = tl.size || 1080, VW = tl.width || SIZE, VH = tl.height || SIZE
;(async () => {
  fs.mkdirSync(outDir, { recursive: true })
  const browser = process.env.FAST
    ? await chromium.launch({ channel: 'chrome', args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu-rasterization', '--enable-webgl'] })
    : await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] })
  const page = await browser.newPage({ viewport: { width: VW, height: VH }, deviceScaleFactor: 1 })
  page.on('pageerror', e => console.log('PAGE ERROR', e.message))
  await page.clock.install({ time: new Date('2026-09-03T12:00:00') })
  await page.goto('file://' + path.resolve(__dirname, '../dist/index.html') + `?w=${VW}&h=${VH}&white=1&state=idle`)
  if (tl.font) { const b64 = fs.readFileSync(tl.font).toString('base64'); await page.addStyleTag({ content: `@font-face { font-family: 'Diatype'; src: url(data:font/ttf;base64,${b64}) format('truetype'); }` }) }
  if (tl.css) await page.addStyleTag({ content: tl.css })
  if (tl.html) await page.evaluate(h => document.body.insertAdjacentHTML('beforeend', h), tl.html)
  if (tl.captionClass) await page.evaluate(cls => { window.pet.setCaption(' '); document.getElementById('cap').classList.add(cls); window.pet.setCaption('') }, tl.captionClass)
  await page.clock.runFor(200)
  const total = Math.ceil(tl.duration * FPS)
  const events = [...tl.events].sort((a, b) => a.t - b.t)
  let ei = 0
  for (let f = 0; f < total; f++) {
    const t = f / FPS
    while (ei < events.length && events[ei].t <= t) {
      const e = events[ei++]
      await page.evaluate(e => {
        const p = window.pet
        if (e.state) p.setState(e.state)
        if (e.caption !== undefined) p.setCaption(e.caption)
        if (e.talking !== undefined) p.setTalking(e.talking)
        if (e.flySpeed !== undefined) p.setFlySpeed(e.flySpeed)
        if (e.calm !== undefined) p.setCalm(e.calm)
        if (e.boop) p.boop()
        if (e.zoom) p.setZoom(e.zoom)
        if (e.zoomTo) p.zoomTo(e.zoomTo[0], e.zoomTo[1])
        if (e.look) p.lookAt(e.look[0], e.look[1])
        if (e.sounds !== undefined) p.setSounds(e.sounds)
        if (e.offset) p.setOffset(e.offset[0], e.offset[1], e.offset[2])
        if (e.ui !== undefined) p.ui(e.ui)
        if (e.type) p.typeInto(e.type[0], e.type[1], e.type[2])
        if (e.reveal) p.reveal(e.reveal[0], e.reveal[1])
      }, e)
    }
    // cursor keyframes: interpolate, show/hide, and make the pet look at it
    if (tl.cursor) {
      const ks = tl.cursor; let seg = null
      for (let i = 0; i < ks.length - 1; i++) if (t >= ks[i][0] && t <= ks[i + 1][0]) { seg = [ks[i], ks[i + 1]]; break }
      if (seg && seg[0][1] != null && seg[1][1] != null) {
        const u0 = (t - seg[0][0]) / (seg[1][0] - seg[0][0]); const u = u0 * u0 * (3 - 2 * u0)
        const x = seg[0][1] + (seg[1][1] - seg[0][1]) * u, y = seg[0][2] + (seg[1][2] - seg[0][2]) * u
        await page.evaluate(([x, y, W, H]) => { window.pet.cursor(x, y); window.pet.lookAt((x / W - 0.5) * 2.2, -(y / H - 0.5) * 2.2) }, [x, y, VW, VH])
      } else {
        await page.evaluate(() => { window.pet.cursor(null); window.pet.lookAt(0, 0) })
      }
    }
    // mic level while listening
    await page.evaluate(t => { if (window.pet.state() === 'listening') window.pet.setLevel(0.35 + 0.5 * Math.abs(Math.sin(t * 9)) * Math.abs(Math.sin(t * 2.3))) }, t)
    await page.clock.runFor(1000 / FPS)
    if (probe) { if (probe.some(pt => Math.abs(pt - t) < 0.5 / FPS)) await page.screenshot({ path: path.join(outDir, `p${t.toFixed(1)}.png`) }) }
    else { await page.screenshot({ path: path.join(outDir, `f${String(f).padStart(5, '0')}.png`) }); if (f % 150 === 0) console.log(`frame ${f}/${total}`) }
  }
  console.log('page clock at end (ms):', await page.evaluate(() => performance.now()))
  await browser.close()
  console.log('done', total, 'frames')
})().catch(e => { console.error(e); process.exit(1) })
