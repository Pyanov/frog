# Working on this repo with Claude Code

This is Frog, a macOS menu-less desktop pet that does on-device dictation and meeting notes. Swift app in `Sources/VoicePet/`, the pet itself is three.js in `web/src/main.js`.

## If someone asks for a different pet

Edit only `web/src/main.js`. Keep this contract, everything else is free:

- `window.pet.setState(name)` for `idle`, `listening`, `thinking`, `done`, `noting`, `confused`, `loading`, `sleeping`.
- `window.pet.setLevel(v)` with v in 0..1, the mic loudness while listening. The pet should visibly react to it.
- `window.pet.lookAt(x, y)` with x, y in -1..1, where the cursor is relative to the pet.
- Transparent canvas: `renderer.setClearColor(0, 0)` and `alpha: true`. The canvas is 260×300 CSS px (`W`, `H`), set in `index.html` and `PetPanel.size` in Swift. Change both if you change one.
- `?bg=1` paints a dark background for previews, `?demo=1` cycles states, `?state=name` forces one.

After editing, run `cd web && node tools/capture.cjs` and look at `web/shots/*.png` before claiming it looks right. Then `./build.sh` and `open build/VoicePet.app`.

Design intent: cute, round, soft toon shading with a dark outline, squash-and-stretch on state changes, always something moving (breathing, blinking, gaze). No UI chrome around the pet.

## Swift side

- Build with `swift build -c release` or `./build.sh` (also builds the web bundle and assembles the .app). No Xcode project; SwiftPM only. Language mode 5.
- `AppDelegate.startListening/stopListening` is the dictation path. `MeetingRecorder` + `NoteProcessor` is the notes path. `Transcriber` is the engine protocol; add engines there.
- Every state change the pet shows goes through `panel.js("pet.setState('…')")`.
- Permissions: Microphone, Speech Recognition, Accessibility, and System Audio Recording (notes). Strings live in `Resources/Info.plist`.
- Debug flags in `main.swift` run without the UI. Use them to test engines with a WAV instead of talking.

## Rules

- Never commit `build/`, `.build/`, `web/dist*`, `web/shots/`, `web/node_modules/`.
- Don't rename the bundle id `ai.learnvector.voicepet`; macOS permissions are keyed on it.
- The frog is `web/src/main.js`. Keep it a frog unless the user asks for another creature.
- Feature branches and pull requests, not pushes to main.
