import assert from 'node:assert/strict'
import { chmod, mkdtemp, rm, writeFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import { firstInstalledBrowser } from './browser.js'

test('selects the first executable installed browser', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'frog-browser-test-'))
  t.after(() => rm(directory, { recursive: true, force: true }))

  const missing = path.join(directory, 'missing')
  const installed = path.join(directory, 'installed')
  await writeFile(installed, '')
  await chmod(installed, 0o755)

  assert.equal(firstInstalledBrowser([missing, installed]), installed)
})

test('returns undefined when no supported browser is executable', () => {
  assert.equal(firstInstalledBrowser(['/not/installed']), undefined)
})
