import { accessSync, constants } from 'node:fs'
import { chromium } from 'playwright'

const installedChromiumBrowsers = [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
]

export function firstInstalledBrowser(browserPaths = installedChromiumBrowsers) {
  return browserPaths.find(executablePath => {
    try {
      accessSync(executablePath, constants.X_OK)
      return true
    } catch {
      return false
    }
  })
}

export function launchBrowser(options = {}) {
  const executablePath = firstInstalledBrowser()
  if (executablePath) {
    console.log(`Using installed browser: ${executablePath}`)
    return chromium.launch({ ...options, executablePath })
  }

  console.log('No supported system browser found; using Playwright Chromium')
  return chromium.launch(options)
}
