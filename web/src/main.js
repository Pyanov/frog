import * as THREE from 'three'

// ---------- setup ----------
const params = new URLSearchParams(location.search)
const VSIZE = parseInt(params.get('size') || '0', 10)
const VW = parseInt(params.get('w') || '0', 10) || VSIZE, VH = parseInt(params.get('h') || '0', 10) || VSIZE
const W = VW || 320, H = VH || 320
if (params.get('bg')) document.body.classList.add('bg')

const canvas = document.getElementById('c')
if (VW) { canvas.width = W; canvas.height = H; canvas.style.width = W + 'px'; canvas.style.height = H + 'px'; document.body.style.width = W + 'px'; document.body.style.height = H + 'px' }
if (params.get('white')) document.body.classList.add('white')
const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true })
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
renderer.setSize(W, H, false)
renderer.setClearColor(0x000000, 0)
renderer.outputColorSpace = THREE.SRGBColorSpace

const scene = new THREE.Scene()
const camera = new THREE.PerspectiveCamera(30, W / H, 0.1, 50)
camera.position.set(0, 0.8, 9.0)
camera.lookAt(0, 0.05, 0)

scene.add(new THREE.HemisphereLight(0xf4fff0, 0xb8d8a0, 0.6))
scene.add(new THREE.AmbientLight(0xffffff, 0.35))
const key = new THREE.DirectionalLight(0xffffff, 1.7); key.position.set(2.5, 4, 3); scene.add(key)
const rim = new THREE.DirectionalLight(0xd8ffe0, 0.9); rim.position.set(-3, 1.5, -3); scene.add(rim)

function gradientMap(steps) {
  const data = new Uint8Array(steps.length * 4)
  steps.forEach((v, i) => { data[i * 4] = data[i * 4 + 1] = data[i * 4 + 2] = v; data[i * 4 + 3] = 255 })
  const t = new THREE.DataTexture(data, steps.length, 1, THREE.RGBAFormat)
  t.minFilter = t.magFilter = THREE.NearestFilter
  t.needsUpdate = true
  return t
}
const toon = gradientMap([120, 185, 235, 255])
const INK = 0x263a1e

// ---------- palette ----------
const GREEN = 0x8fd46a, GREEN_DARK = 0x6bb54f, GREEN_LIGHT = 0xc4eaa4, CREAM = 0xeef4c6, BLUSH = 0xffa8c2, TONGUE = 0xff6f9f, EYE_INK = 0x1e1b2b

const toonMat = (color) => new THREE.MeshToonMaterial({ color, gradientMap: toon })
const outlineMat = new THREE.MeshBasicMaterial({ color: INK, side: THREE.BackSide })
function withOutline(mesh, thick = 1.04) {
  const o = new THREE.Mesh(mesh.geometry, outlineMat)
  o.scale.setScalar(thick)
  mesh.add(o)
  return mesh
}
function onSurface(obj, x, y, r = 1) {
  const z = Math.sqrt(Math.max(0, r * r - x * x - y * y))
  obj.position.set(x, y, z)
  obj.lookAt(x * 3, y * 3, z * 3)
  return obj
}

// ---------- the frog ----------
const pet = new THREE.Group()           // squash/stretch + hover
const head = new THREE.Group()          // rotation toward cursor
pet.add(head)
scene.add(pet)

// one wide low dome for head and body
const body = withOutline(new THREE.Mesh(new THREE.SphereGeometry(1, 96, 96), toonMat(GREEN)), 1.03)
body.scale.set(1.25, 0.95, 1.05)
head.add(body)

// eye bumps grow out of the dome; the eyes sit inside them
const bumpL = withOutline(new THREE.Mesh(new THREE.SphereGeometry(0.46, 48, 48), toonMat(GREEN)), 1.04)
bumpL.position.set(-0.5, 0.74, 0.3)
const bumpR = withOutline(new THREE.Mesh(new THREE.SphereGeometry(0.4, 48, 48), toonMat(GREEN)), 1.04)
bumpR.position.set(0.55, 0.72, 0.32)
head.add(bumpL, bumpR)

function makeEye(r, pupilR, derpX, derpY, lazy) {
  const g = new THREE.Group()
  const white = withOutline(new THREE.Mesh(new THREE.SphereGeometry(r, 40, 40), toonMat(0xffffff)), 1.05)
  const pupil = new THREE.Group()
  const dark = new THREE.Mesh(new THREE.SphereGeometry(pupilR, 32, 32), new THREE.MeshBasicMaterial({ color: EYE_INK }))
  const shine = new THREE.Mesh(new THREE.SphereGeometry(pupilR * 0.4, 16, 16), new THREE.MeshBasicMaterial({ color: 0xffffff }))
  shine.position.set(-pupilR * 0.35, pupilR * 0.4, pupilR * 0.78)
  pupil.add(dark, shine)
  pupil.position.z = r * 0.82
  // lid: a green cap that slides down over the eye
  const lid = new THREE.Mesh(new THREE.SphereGeometry(r * 1.07, 32, 16, 0, Math.PI * 2, 0, 1.3), toonMat(GREEN))
  lid.rotation.x = 0.55
  // fully closed: green ball with a sleepy line
  const closed = new THREE.Group()
  const ball = withOutline(new THREE.Mesh(new THREE.SphereGeometry(r * 1.03, 32, 32), toonMat(GREEN)), 1.05)
  const arc = new THREE.Mesh(new THREE.TorusGeometry(r * 0.48, 0.028, 8, 24, Math.PI), new THREE.MeshBasicMaterial({ color: INK }))
  arc.position.set(0, -r * 0.05, r * 1.0); arc.rotation.z = Math.PI
  closed.add(ball, arc); closed.visible = false
  g.add(white, pupil, lid, closed)
  g.userData = { r, pupil, lid, closed, derpX, derpY, lazy, base: null }
  return g
}
const eyeL = makeEye(0.36, 0.19, -0.05, 0.04, 0.38), eyeR = makeEye(0.31, 0.15, 0.07, -0.02, 0.58)
eyeL.position.set(-0.5, 0.74, 0.5); eyeR.position.set(0.55, 0.72, 0.5)
eyeL.userData.base = eyeL.position.clone(); eyeR.userData.base = eyeR.position.clone()
head.add(eyeL, eyeR)
let eyePop = 0, eyePopV = 0

// nostrils
;[-0.13, 0.13].forEach(x => {
  const n = new THREE.Mesh(new THREE.SphereGeometry(0.03, 12, 12), new THREE.MeshBasicMaterial({ color: INK }))
  n.position.set(x, 0.26, 1.02); head.add(n)
})

// the mouth: a thin line that hugs the face, wide and gently upturned, a bit crooked
function facePoint(x, y, push = 0.02) {
  const z = Math.sqrt(Math.max(0.0001, 1 - (x / 1.25) ** 2 - (y / 0.95) ** 2)) * 1.05 + push
  return new THREE.Vector3(x, y, z)
}
const mouthPts = []
for (let i = 0; i <= 40; i++) {
  const u = i / 40 - 0.5               // -0.5..0.5
  const x = u * 1.9 + 0.03
  const y = -0.17 + (u * u) * 0.75 + u * 0.06   // corners up, slightly crooked
  mouthPts.push(facePoint(x, y, 0.025))
}
const mouth = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(mouthPts), 60, 0.028, 8, false), new THREE.MeshBasicMaterial({ color: INK }))
head.add(mouth)
const mouthO = new THREE.Mesh(new THREE.SphereGeometry(1, 24, 24), new THREE.MeshBasicMaterial({ color: INK }))
mouthO.scale.set(0.18, 0.13, 0.05); mouthO.position.copy(facePoint(0.02, -0.22, 0)); mouthO.visible = false
head.add(mouthO)

// cheek pouches: hidden at rest, puff out beside the mouth while you talk. Blush rides on them.
const cheekMat = new THREE.MeshBasicMaterial({ color: BLUSH, transparent: true, opacity: 0.8 })
const pouches = [-1, 1].map(side => {
  const g = new THREE.Group()
  const ball = withOutline(new THREE.Mesh(new THREE.SphereGeometry(1, 40, 40), toonMat(GREEN)), 1.04)
  const blush = new THREE.Mesh(new THREE.CircleGeometry(0.22, 32), cheekMat)
  blush.position.set(side * 0.15, -0.05, 0.98)
  g.add(ball, blush)
  g.position.copy(facePoint(side * 0.78, -0.16, -0.12))
  g.userData.side = side
  head.add(g)
  return g
})
// resting blush dots on the face
;[-0.9, 0.9].forEach(x => {
  const c = new THREE.Mesh(new THREE.CircleGeometry(0.085, 32), cheekMat)
  c.position.copy(facePoint(x * 0.9, -0.1, 0.09))
  head.add(c)
})

// tongue
const tongue = new THREE.Group()
{
  const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.075, 0.06, 1, 12), toonMat(TONGUE))
  shaft.rotation.x = Math.PI / 2; shaft.position.z = 0.5
  const tip = new THREE.Mesh(new THREE.SphereGeometry(0.1, 16, 16), toonMat(TONGUE)); tip.position.z = 1
  tongue.add(shaft, tip)
  tongue.position.set(0.05, -0.2, 1.0); tongue.rotation.set(-1.0, 0.75, 0, 'YXZ')
  tongue.scale.set(1, 1, 0.001)
  head.add(tongue)
}

// legs, sitting frog seen from the front:
// front legs come straight down at the sides of the body to splayed hands;
// hind legs are folded haunches behind them, with the webbed feet sticking out at the outer edges.
const limbMat = toonMat(GREEN)
const padMat = toonMat(GREEN_LIGHT)
function capsule(r, len, mat = limbMat, thick = 1.05) {
  return withOutline(new THREE.Mesh(new THREE.CapsuleGeometry(r, len, 6, 16), mat), thick)
}
function toe(parent, r, len, angleY, x, z, padR) {
  const g = new THREE.Group()
  const seg = capsule(r, len)
  seg.rotation.x = Math.PI / 2; seg.position.z = len / 2
  const pad = withOutline(new THREE.Mesh(new THREE.SphereGeometry(padR, 16, 16), padMat), 1.06)
  pad.position.z = len + r * 0.5
  g.add(seg, pad)
  g.position.set(x, 0, z); g.rotation.y = angleY
  parent.add(g)
}
;[-1, 1].forEach(side => {
  // haunch: folded hind leg, a big rounded mass low on the side, behind the arm
  const haunch = withOutline(new THREE.Mesh(new THREE.SphereGeometry(1, 40, 40), limbMat), 1.04)
  haunch.scale.set(0.55, 0.46, 0.5); haunch.position.set(side * 1.02, -0.52, -0.02)
  pet.add(haunch)
  // hind foot: long, points outward and forward from under the haunch
  const hfoot = new THREE.Group()
  hfoot.position.set(side * 1.22, -1.02, 0.2); hfoot.rotation.y = side * -0.95
  const hpad = withOutline(new THREE.Mesh(new THREE.SphereGeometry(1, 24, 24), limbMat), 1.05)
  hpad.scale.set(0.2, 0.09, 0.16); hfoot.add(hpad)
  toe(hfoot, 0.06, 0.34, -0.35, -0.11, 0.06, 0.08)
  toe(hfoot, 0.065, 0.42, 0, 0, 0.08, 0.085)
  toe(hfoot, 0.06, 0.34, 0.35, 0.11, 0.06, 0.08)
  pet.add(hfoot)

  // front leg: thick, straight down from the side of the body
  const arm = capsule(0.16, 0.42)
  arm.position.set(side * 0.84, -0.62, 0.5); arm.rotation.set(-0.12, 0, side * 0.08)
  pet.add(arm)
  // hand: flat, toes splayed forward and outward
  const hand = new THREE.Group()
  hand.position.set(side * 0.86, -1.02, 0.66); hand.rotation.y = side * -0.3
  const pad = withOutline(new THREE.Mesh(new THREE.SphereGeometry(1, 24, 24), limbMat), 1.05)
  pad.scale.set(0.2, 0.09, 0.16); hand.add(pad)
  toe(hand, 0.055, 0.26, -0.45, -0.1, 0.06, 0.07)
  toe(hand, 0.058, 0.3, 0, 0, 0.08, 0.075)
  toe(hand, 0.055, 0.26, 0.45, 0.1, 0.06, 0.07)
  pet.add(hand)
})

// the fly
const fly = new THREE.Group()
{
  const b = new THREE.Mesh(new THREE.SphereGeometry(0.05, 12, 12), new THREE.MeshBasicMaterial({ color: 0x2a2233 }))
  const wing = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.55 })
  const w1 = new THREE.Mesh(new THREE.CircleGeometry(0.05, 12), wing); w1.position.set(-0.04, 0.045, 0); w1.rotation.x = -1.2
  const w2 = w1.clone(); w2.position.x = 0.04
  fly.add(b, w1, w2)
  fly.userData = { wings: [w1, w2] }
  scene.add(fly)
}
let flyEaten = 0   // time left hidden
let flySpeed = 1, flyPhase = 0   // fly pace; videos slow it down
let calm = 0   // 0..1: slower, softer motion for videos (gentler spring, rarer hops, deeper breathing)

// retro military headset: on while taking notes
const phones = new THREE.Group()
let led
{
  const olive = toonMat(0x6b7a3f), oliveDark = toonMat(0x4f5a2e), leather = toonMat(0x4a3728)
  const khaki = new THREE.MeshBasicMaterial({ color: 0xc9b98a })
  const grille = new THREE.MeshBasicMaterial({ color: 0x2b3326 })
  const steel = new THREE.MeshBasicMaterial({ color: 0x9aa0a6 })
  const rubber = toonMat(0x2a2a2a)
  const band = withOutline(new THREE.Mesh(new THREE.TorusGeometry(1.07, 0.075, 12, 48, Math.PI), olive), 1.06)
  band.position.y = 0.05
  const pad = withOutline(new THREE.Mesh(new THREE.TorusGeometry(1.1, 0.085, 12, 24, Math.PI * 0.42), leather), 1.05)
  pad.position.y = 0.05; pad.rotation.z = Math.PI * 0.29
  const rivetL = new THREE.Mesh(new THREE.SphereGeometry(0.035, 12, 12), steel); rivetL.position.set(-0.62, 0.95, 0.1)
  const rivetR = rivetL.clone(); rivetR.position.x = 0.62
  function can(side) {
    const g = new THREE.Group()
    const cup = withOutline(new THREE.Mesh(new THREE.SphereGeometry(1, 32, 32), oliveDark), 1.05)
    cup.scale.set(0.24, 0.32, 0.26)
    const rimm = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.035, 10, 32), khaki)
    rimm.position.x = side * 0.2; rimm.rotation.y = Math.PI / 2
    const disc = new THREE.Mesh(new THREE.CircleGeometry(0.17, 32), grille)
    disc.position.x = side * 0.215; disc.rotation.y = side * Math.PI / 2
    const screw = new THREE.Mesh(new THREE.SphereGeometry(0.04, 12, 12), steel)
    screw.position.x = side * 0.23
    g.add(cup, rimm, disc, screw)
    g.position.set(side * 1.08, 0.02, 0.06)
    return g
  }
  const canL = can(-1), canR = can(1)
  const armCurve = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-1.0, -0.12, 0.3), new THREE.Vector3(-0.85, -0.42, 0.72), new THREE.Vector3(-0.45, -0.5, 0.98), new THREE.Vector3(-0.22, -0.46, 1.06)])
  const arm = new THREE.Mesh(new THREE.TubeGeometry(armCurve, 24, 0.028, 8, false), rubber)
  const capsule = withOutline(new THREE.Mesh(new THREE.SphereGeometry(1, 20, 20), rubber), 1.06)
  capsule.scale.set(0.085, 0.07, 0.07); capsule.position.set(-0.19, -0.46, 1.08)
  const capsuleTip = new THREE.Mesh(new THREE.SphereGeometry(0.03, 10, 10), steel); capsuleTip.position.set(-0.19, -0.46, 1.15)
  const coilPts = []
  for (let i = 0; i <= 90; i++) { const a = i / 90 * Math.PI * 2 * 6; coilPts.push(new THREE.Vector3(1.12 + Math.cos(a) * 0.05, -0.22 - i / 90 * 0.62, 0.12 + Math.sin(a) * 0.05)) }
  const coil = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(coilPts), 180, 0.014, 6, false), rubber)
  led = new THREE.Mesh(new THREE.SphereGeometry(0.035, 12, 12), new THREE.MeshBasicMaterial({ color: 0xff3b3b }))
  led.position.set(-0.99, 0.24, 0.31)
  phones.add(band, pad, rivetL, rivetR, canL, canR, arm, capsule, capsuleTip, coil, led)
  phones.position.y = 0.22
  phones.scale.setScalar(0.001)
  head.add(phones)
}
let ph = 0, phV = 0

// soft floor shadow
function radialTexture(inner, outer) {
  const c = document.createElement('canvas'); c.width = c.height = 128
  const ctx = c.getContext('2d')
  const g = ctx.createRadialGradient(64, 64, 4, 64, 64, 64)
  g.addColorStop(0, inner); g.addColorStop(1, outer)
  ctx.fillStyle = g; ctx.fillRect(0, 0, 128, 128)
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace
  return t
}
const shadow = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 2.6), new THREE.MeshBasicMaterial({ map: radialTexture('rgba(30,40,20,0.35)', 'rgba(30,40,20,0)'), transparent: true, depthWrite: false }))
shadow.rotation.x = -Math.PI / 2; shadow.position.y = -1.22; shadow.scale.set(1.7, 0.55, 1)
scene.add(shadow)

// listening glow
const halo = new THREE.Mesh(new THREE.PlaneGeometry(4.6, 4.6), new THREE.MeshBasicMaterial({ map: radialTexture('rgba(190,255,150,0.9)', 'rgba(190,255,150,0)'), color: 0xffffff, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false }))
halo.position.z = -1.2
scene.add(halo)

// sparkles
const SPARKS = 48
const sparkGeo = new THREE.BufferGeometry()
const sparkPos = new Float32Array(SPARKS * 3)
sparkGeo.setAttribute('position', new THREE.BufferAttribute(sparkPos, 3))
const sparks = new THREE.Points(sparkGeo, new THREE.PointsMaterial({ color: 0xfff1a8, size: 0.3, transparent: true, opacity: 0, map: radialTexture('rgba(255,255,255,1)', 'rgba(255,255,255,0)'), blending: THREE.AdditiveBlending, depthWrite: false }))
scene.add(sparks)
const sparkVel = new Float32Array(SPARKS * 3)
let sparkLife = 0

// sleepy z's and a question mark
function textSprite(txt) {
  const c = document.createElement('canvas'); c.width = 64; c.height = 64
  const ctx = c.getContext('2d')
  ctx.font = 'bold 44px -apple-system, Helvetica, sans-serif'
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle'
  ctx.lineWidth = 6; ctx.strokeStyle = '#2f3a24'; ctx.strokeText(txt, 32, 34)
  ctx.fillStyle = '#ffffff'; ctx.fillText(txt, 32, 34)
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, transparent: true, opacity: 0, depthWrite: false }))
  s.scale.setScalar(0.45)
  return s
}
const zs = [textSprite('z'), textSprite('z'), textSprite('z')]
zs.forEach(z => scene.add(z))
const qmark = textSprite('?'); qmark.scale.setScalar(0.7); scene.add(qmark)

// ---------- sounds ----------
const sfx = {
  enabled: true, ctx: null,
  ac() { if (!this.ctx) this.ctx = new (window.AudioContext || window.webkitAudioContext)(); if (this.ctx.state === 'suspended') this.ctx.resume(); return this.ctx },
  tone({ type = 'sine', from = 440, to = from, dur = 0.12, vol = 0.25, delay = 0, attack = 0.005, curve = 'exp' }) {
    const c = this.ac(), t0 = c.currentTime + delay
    const o = c.createOscillator(), g = c.createGain()
    o.type = type
    o.frequency.setValueAtTime(from, t0)
    if (curve === 'exp') o.frequency.exponentialRampToValueAtTime(Math.max(20, to), t0 + dur)
    else o.frequency.linearRampToValueAtTime(to, t0 + dur)
    g.gain.setValueAtTime(0.0001, t0)
    g.gain.exponentialRampToValueAtTime(vol, t0 + attack)
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur)
    o.connect(g).connect(c.destination)
    o.start(t0); o.stop(t0 + dur + 0.02)
  },
  noise({ dur = 0.08, vol = 0.15, delay = 0, freq = 1800, q = 1.2 }) {
    const c = this.ac(), t0 = c.currentTime + delay
    const n = Math.floor(c.sampleRate * dur), buf = c.createBuffer(1, n, c.sampleRate), d = buf.getChannelData(0)
    for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / n)
    const src = c.createBufferSource(); src.buffer = buf
    const f = c.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = q
    const g = c.createGain(); g.gain.setValueAtTime(vol, t0); g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur)
    src.connect(f).connect(g).connect(c.destination); src.start(t0)
  },
  play(name) {
    if (!this.enabled) return
    try {
      switch (name) {
        case 'pop':      this.tone({ from: 420, to: 150, dur: 0.12, vol: 0.28 }); this.noise({ dur: 0.03, vol: 0.08, freq: 2500 }); break
        case 'gulp':     this.tone({ from: 260, to: 90, dur: 0.16, vol: 0.22 }); this.tone({ from: 150, to: 220, dur: 0.09, vol: 0.14, delay: 0.15 }); break
        case 'ding':     this.tone({ from: 1046, dur: 0.22, vol: 0.18 }); this.tone({ from: 1318, dur: 0.32, vol: 0.18, delay: 0.09 }); this.tone({ from: 2637, dur: 0.18, vol: 0.06, delay: 0.16 }); break
        case 'slurp':    this.tone({ type: 'triangle', from: 300, to: 900, dur: 0.1, vol: 0.14 }); this.noise({ dur: 0.06, vol: 0.06, freq: 3500, delay: 0.08 }); break
        case 'huh':      this.tone({ type: 'triangle', from: 420, to: 300, dur: 0.16, vol: 0.18, curve: 'lin' }); this.tone({ type: 'triangle', from: 300, to: 440, dur: 0.18, vol: 0.16, delay: 0.17, curve: 'lin' }); break
        case 'radioOn':  this.noise({ dur: 0.12, vol: 0.12, freq: 1500, q: 0.8 }); this.tone({ type: 'square', from: 1200, dur: 0.06, vol: 0.06, delay: 0.1 }); this.tone({ type: 'square', from: 1600, dur: 0.07, vol: 0.06, delay: 0.18 }); break
        case 'radioOff': this.tone({ type: 'square', from: 1200, dur: 0.06, vol: 0.06 }); this.tone({ type: 'square', from: 800, dur: 0.1, vol: 0.06, delay: 0.09 }); this.noise({ dur: 0.08, vol: 0.08, freq: 1200, q: 0.8, delay: 0.18 }); break
        case 'boop':     this.tone({ from: 600, to: 800, dur: 0.07, vol: 0.2 }); this.tone({ from: 800, to: 420, dur: 0.1, vol: 0.16, delay: 0.07 }); break
        case 'ribbit':   this.tone({ type: 'sawtooth', from: 140, to: 95, dur: 0.16, vol: 0.14 }); this.tone({ type: 'sawtooth', from: 120, to: 170, dur: 0.14, vol: 0.12, delay: 0.17 }); break
      }
    } catch (e) { /* audio not available */ }
  },
}

// ---------- state ----------
let state = 'idle'
let stateT = 0
let level = 0, levelSmooth = 0
const look = { x: 0, y: 0, tx: 0, ty: 0 }
let sq = 0, sqV = 0
let blinkT = 2.5, blink = 0
let tongueOut = 0, tongueV = 0, tongueUntil = 0
let hopT = 5 + Math.random() * 6
let talking = false
const slide = { x: 0, y: 0, tx: 0, ty: 0, speed: 3 }
const cam = { tz: camera.position.z, speed: 0 }

function impulse(v) { sqV += v * (1 - 0.5 * calm) }

window.pet = {
  name: 'frog',
  setState(s) {
    if (s === state) return
    const prev = state
    state = s; stateT = 0
    if (s === 'listening') { impulse(-4); sfx.play('pop') }
    if (s === 'thinking' && prev === 'listening') sfx.play('gulp')
    if (s === 'done') { impulse(9); burst(); sfx.play('slurp'); sfx.play('ding'); tongueUntil = 0.55; flyEaten = 6 }
    if (s === 'confused') { impulse(3); sfx.play('huh') }
    if (s === 'noting') { impulse(-3); sfx.play('radioOn') }
    if (prev === 'noting' && s !== 'noting') sfx.play('radioOff')
    if (s === 'idle') { impulse(2); if (prev === 'loading' || prev === 'sleeping') sfx.play('ribbit') }
  },
  setLevel(v) { level = Math.max(0, Math.min(1, v)) },
  lookAt(x, y) { look.tx = x; look.ty = y },
  setSounds(on) { sfx.enabled = !!on },
  setTalking(on) { talking = !!on },
  setFlySpeed(k) { flySpeed = Math.max(0, +k || 0) },
  setCalm(c) { calm = Math.max(0, Math.min(1, +c || 0)) },
  setOffset(x, y, secs) { slide.tx = x; slide.ty = y; slide.speed = secs ? 1 / Math.max(0.05, secs) : 3 },
  ui(html) { let u = document.getElementById('ui'); if (!u) { u = document.createElement('div'); u.id = 'ui'; document.body.appendChild(u) } u.innerHTML = html || '' },
  typeInto(id, text, ms) { const el = document.getElementById(id); if (!el) return; let i = 0; const step = Math.max(12, ms / Math.max(1, text.length)); el.textContent = ''; const tick = () => { i++; el.textContent = text.slice(0, i); if (i < text.length) setTimeout(tick, step) }; setTimeout(tick, step) },
  reveal(cls, everyMs) { const els = document.querySelectorAll('.' + cls); els.forEach((el, i) => setTimeout(() => el.classList.add('on'), i * everyMs)) },
  setCaption(text) { let c = document.getElementById('cap'); if (!c) { c = document.createElement('div'); c.id = 'cap'; document.body.appendChild(c) } c.textContent = text || ''; c.style.opacity = text ? 1 : 0 },
  setZoom(z) { camera.position.z = z; cam.tz = z; cam.speed = 0 },
  zoomTo(z, secs) { cam.tz = z; cam.speed = 1 / Math.max(0.05, secs) },
  cursor(x, y) { let c = document.getElementById('cur'); if (!c) { c = document.createElement('div'); c.id = 'cur'; c.innerHTML = '<svg width="56" height="70" viewBox="0 0 24 30"><path d="M2 2 L2 24 L8 18 L12 28 L16 26 L12 17 L20 17 Z" fill="#fff" stroke="#1d1d1f" stroke-width="1.6" stroke-linejoin="round"/></svg>'; document.body.appendChild(c) } if (x == null) { c.style.display = 'none'; return } c.style.display = 'block'; c.style.left = x + 'px'; c.style.top = y + 'px' },
  boop() { impulse(6); sfx.play('boop') },
  state: () => state,
}

function burst() {
  for (let i = 0; i < SPARKS; i++) {
    const a = Math.random() * Math.PI * 2, b = (Math.random() - 0.5) * Math.PI
    const sp = 1.8 + Math.random() * 2.8
    sparkPos[i * 3] = 0; sparkPos[i * 3 + 1] = 0.1; sparkPos[i * 3 + 2] = 0.5
    sparkVel[i * 3] = Math.cos(a) * Math.cos(b) * sp
    sparkVel[i * 3 + 1] = Math.sin(b) * sp + 1.5
    sparkVel[i * 3 + 2] = Math.sin(a) * Math.cos(b) * sp * 0.5
  }
  sparkLife = 1
}

// ---------- loop ----------
const clock = new THREE.Clock()
function frame() {
  requestAnimationFrame(frame)
  const dt = Math.min(clock.getDelta(), 1 / 20)
  const t = clock.elapsedTime
  stateT += dt

  const k = 140 - 60 * calm, d = 11 + 12 * calm
  sqV += (-k * sq - d * sqV) * dt
  sq += sqV * dt

  const lk = 6 - 4 * calm
  look.x += (look.tx - look.x) * Math.min(1, dt * lk)
  look.y += (look.ty - look.y) * Math.min(1, dt * lk)
  levelSmooth += (level - levelSmooth) * Math.min(1, dt * 14)

  let hover = Math.sin(t * (1.5 - 1.0 * calm)) * (0.03 - 0.015 * calm)
  let breathe = 1 + Math.sin(t * (2.0 - 1.3 * calm)) * (0.012 + 0.023 * calm)
  let throatScale = 1
  const headFollow = 1 - 0.55 * calm   // calm: eyes travel more than the head
  let rotX = -look.y * 0.18 * headFollow, rotY = look.x * 0.32 * headFollow, rotZ = 0
  let eyeOpen = 1
  let mouthOpen = 0
  let haloOpacity = 0
  let zOpacity = 0, qOpacity = 0
  let showGrin = true

  // blink
  blinkT -= dt
  if (blinkT <= 0) { blink = 0.14; blinkT = 2.5 + Math.random() * 4 }
  if (blink > 0) { blink -= dt; eyeOpen = blink > 0.07 ? 0 : 1 }

  // idle hop now and then
  hopT -= dt
  if (hopT <= 0 && state === 'idle') { impulse(-7 + 3 * calm); hopT = calm ? 10 + Math.random() * 4 : 6 + Math.random() * 8 }

  if (talking && (state === 'idle' || state === 'done')) {
    const m = 0.5 + 0.5 * (0.6 * Math.sin(t * (6.1 - 1.6 * calm)) + 0.4 * Math.sin(t * (3.7 - 1.1 * calm) + 1.0))
    mouthOpen = 0.12 + m * 0.45
    showGrin = false
    throatScale = 1 + 0.12 + m * 0.12
  }
  switch (state) {
    case 'listening': {
      throatScale = 1 + 0.5 + levelSmooth * 0.9
      mouthOpen = 0.4 + levelSmooth * 1.4
      showGrin = false
      rotX += 0.1
      hover = Math.sin(t * (6 - 4 * calm)) * 0.02 * (0.3 + levelSmooth)
      haloOpacity = 0.18 + levelSmooth * 0.5
      halo.scale.setScalar(1 + levelSmooth * 0.25 + Math.sin(t * 5) * 0.02)
      break
    }
    case 'thinking': {
      rotZ = Math.sin(t * 3.2) * 0.1
      rotY += Math.sin(t * 1.5) * 0.25
      rotX -= 0.15
      mouthOpen = 0.3; showGrin = false
      throatScale = 1 + 0.35 + Math.sin(t * (8 - 5 * calm)) * 0.08
      hover += Math.abs(Math.sin(t * 5)) * 0.06
      break
    }
    case 'done': {
      eyeOpen = Math.min(eyeOpen, 0.6 + 0.4 * Math.abs(Math.sin(stateT * 3)))
      if (stateT > 1.1) window.pet.setState('idle')
      break
    }
    case 'noting': {
      led.scale.setScalar(1 + Math.max(0, Math.sin(t * 5)) * 0.7)
      rotX += 0.06 + Math.sin(t * 2.2) * 0.05
      rotY += Math.sin(t * 0.7) * 0.12
      hover = Math.sin(t * 1.2) * 0.04
      break
    }
    case 'confused': {
      rotZ = 0.22 + Math.sin(t * 9) * 0.03
      qOpacity = Math.min(1, stateT * 4)
      showGrin = false; mouthOpen = 0.12
      if (stateT > 1.8) window.pet.setState('idle')
      break
    }
    case 'loading':
    case 'sleeping': {
      eyeOpen = 0
      breathe = 1 + Math.sin(t * 1.4) * 0.03
      throatScale = 1
      rotZ = Math.sin(t * 1.4) * 0.05
      rotX = 0.1; rotY *= 0.3
      zOpacity = 1
      break
    }
    default: break
  }

  // eyes bulge forward while listening
  const popTarget = state === 'listening' ? 1 : (state === 'thinking' ? 0.3 : 0)
  eyePopV += ((popTarget - eyePop) * 110 - eyePopV * 7) * dt
  eyePop += eyePopV * dt

  // headset
  const phTarget = state === 'noting' ? 1 : 0
  phV += ((phTarget - ph) * 120 - phV * 8) * dt
  ph += phV * dt
  phones.scale.setScalar(Math.max(0.001, ph) * 1.3)

  // tongue
  tongueUntil -= dt
  const tTarget = tongueUntil > 0 ? 1 : 0
  tongueV += ((tTarget - tongueOut) * 260 - tongueV * 12) * dt
  tongueOut += tongueV * dt
  tongue.scale.set(1, 1, Math.max(0.001, tongueOut * 1.7))
  tongue.visible = tongueOut > 0.05

  // apply
  const s = breathe
  pet.scale.set(s * (1 + sq * 0.55), s * (1 - sq), s * (1 + sq * 0.55))
  if (cam.speed > 0) camera.position.z += (cam.tz - camera.position.z) * Math.min(1, dt * cam.speed * 2.5)
  slide.x += (slide.tx - slide.x) * Math.min(1, dt * slide.speed * 2.2)
  slide.y += (slide.ty - slide.y) * Math.min(1, dt * slide.speed * 2.2)
  pet.position.x = slide.x
  pet.position.y = hover - Math.max(0, sq) * 0.15 + slide.y
  shadow.position.x = slide.x; shadow.position.y = -1.22 + slide.y
  head.rotation.set(rotX, rotY, rotZ)
  const closed = eyeOpen < 0.15
  ;[eyeL, eyeR].forEach((e, i) => {
    const { r, pupil, lid, closed: cl, derpX, derpY, base, lazy } = e.userData
    e.position.set(base.x, base.y + eyePop * 0.08, base.z + eyePop * 0.16)
    e.scale.setScalar(1 + eyePop * 0.14)
    cl.visible = closed
    e.children[0].visible = !closed; pupil.visible = !closed; lid.visible = !closed
    let roll = state === 'thinking' ? t * 4 : 0
    pupil.position.x = closed ? 0 : (look.x * r * 0.42 + derpX + (roll ? Math.cos(roll) * r * 0.3 : 0))
    pupil.position.y = closed ? 0 : (look.y * r * 0.38 + derpY + (roll ? Math.sin(roll) * r * 0.3 : 0))
    const droop = state === 'confused' ? (i === 1 ? 0.85 : 0.3) : (state === 'listening' || state === 'done' ? 0 : lazy)
    lid.visible = !closed && droop > 0.04
    lid.position.y = r * (0.7 - droop * 0.85)
  })
  mouth.visible = showGrin
  mouthO.visible = !showGrin
  mouthO.scale.set(0.16 + mouthOpen * 0.08, 0.1 + mouthOpen * 0.16, 0.05)
  // cheeks puff with your voice, head widens a touch
  const inf = Math.max(0, throatScale - 1)
  pouches.forEach(g => {
    const r = Math.max(0.001, inf * 0.42)
    g.scale.set(r * 1.1, r, r * 0.9)
    g.visible = r > 0.03
    g.position.x = g.userData.side * (0.78 + inf * 0.12)
  })
  head.scale.set(1 + inf * 0.08, 1, 1)
  halo.material.opacity += (haloOpacity - halo.material.opacity) * Math.min(1, dt * 10)
  halo.rotation.z = t * 0.3
  shadow.material.opacity = 1 - Math.max(0, hover) * 3
  shadow.scale.set(1.7 - hover * 1.5, 0.55 - hover * 0.6, 1)

  // fly buzzes around, hides after being eaten
  flyEaten -= dt
  fly.visible = flyEaten <= 0 && state !== 'noting'
  flyPhase += dt * 1.3 * flySpeed
  const fa = flyPhase, ft = flyPhase / 1.3
  fly.position.set(Math.cos(fa) * 1.5 + Math.sin(ft * 7) * 0.08, 0.9 + Math.sin(fa * 1.7) * 0.5 + Math.sin(ft * 11) * 0.05, Math.sin(fa) * 0.9 + 0.3)
  fly.userData.wings.forEach((w, i) => { w.rotation.y = Math.sin(t * 60 + i * Math.PI) * 0.8 })

  // sparkles
  if (sparkLife > 0) {
    sparkLife -= dt * 1.1
    for (let i = 0; i < SPARKS; i++) {
      sparkVel[i * 3 + 1] -= 6 * dt
      sparkPos[i * 3] += sparkVel[i * 3] * dt
      sparkPos[i * 3 + 1] += sparkVel[i * 3 + 1] * dt
      sparkPos[i * 3 + 2] += sparkVel[i * 3 + 2] * dt
    }
    sparkGeo.attributes.position.needsUpdate = true
    sparks.material.opacity = Math.max(0, sparkLife)
  } else sparks.material.opacity = 0

  zs.forEach((z, i) => {
    const phz = (t * 0.5 + i / 3) % 1
    z.position.set(1.1 + phz * 0.5 + i * 0.05, 0.8 + phz * 1.1, 0.5)
    z.scale.setScalar(0.3 + phz * 0.35)
    z.material.opacity += ((zOpacity * (1 - phz) * Math.min(1, phz * 4)) - z.material.opacity) * Math.min(1, dt * 8)
  })
  qmark.position.set(1.15 + Math.sin(t * 5) * 0.05, 1.15, 0.5)
  qmark.material.opacity += (qOpacity - qmark.material.opacity) * Math.min(1, dt * 8)

  renderer.render(scene, camera)
}
frame()

// ---------- browser-only demo (?demo=1) ----------
if (params.get('demo')) {
  const states = ['idle', 'listening', 'thinking', 'done', 'noting', 'confused', 'sleeping']
  let i = 0
  setInterval(() => { i = (i + 1) % states.length; window.pet.setState(states[i]) }, 2600)
  setInterval(() => { if (state === 'listening') window.pet.setLevel(Math.abs(Math.sin(performance.now() / 180)) * 0.9) }, 33)
  window.addEventListener('mousemove', e => window.pet.lookAt((e.clientX / W - 0.5) * 2, -(e.clientY / H - 0.5) * 2))
}
const forced = params.get('state')
if (forced) { window.pet.setState(forced); if (forced === 'listening') window.pet.setLevel(0.7) }
