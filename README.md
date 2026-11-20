# M.I.S.A.

A floating assistant for macOS. She sits anywhere on your screen, above every app, and opens into a chat when you click her or press **⌥Space**. Everything runs on your Mac: no account, no API key, no subscription.

## What she can do

**Drop files on her**, then pick:

| Ability | How it works |
| --- | --- |
| Convert images to JPG | `sips`, built into macOS (great for iPhone HEIC photos) |
| Shrink images | Longest side 1600 px, saved as a new `… small.jpg` |
| Combine images into one PDF | PDFKit, in file-name order |
| Convert videos to MP4 | `avconvert`, built into macOS |
| Copy text for AI | Text from PDFs, Word, RTF, web pages, code files, or a whole code folder (skips `node_modules`, `.git`, builds) goes to your clipboard |
| Prep for Canvas | Makes a PDF named like `Than_Homework_6_2026-11-19.pdf` |
| Mark disposable | Moves files to `~/Disposable` ([Disposable Downloads](https://github.com/The-Hieusss/disposable-downloads) trashes them on a timer) |

**Or ask her to:**

- start a focus timer: "focus for 25 min", "take a break", "pause", "how much time left". A ring around her halo counts down, and she chimes when it's done
- do math: "15% of $84.50", "18% tip on $64.20", "20% off $60", "sqrt(2) * 3". It uses a small parser that only understands numbers, operators and a few functions (like `safe_eval` in a calculator agent), so nothing is executed as code
- convert units: "3 cups in ml", "72 f to c", "how many oz in 2 lb", "10 gb in mb". Conversion factors come from Apple's `Measurement` API; cups and spoons are US measures
- tidy screenshots off your Desktop into `~/Screenshots/<year-month>/`, or trash ones older than 7 days
- save new screenshots to `~/Screenshots` instead of the Desktop
- tidy downloads older than 30 days (moves them to Disposable)
- show what's using your disk (read-only)
- show what's in Disposable, or "keep" a file from it

New files always go next to the originals, and originals are never changed. Anything that moves many files or sends things to the Trash shows a **confirm card** first, and nothing happens until you click it. Actions are logged to `~/Library/Logs/misa.log`.

The first time she touches your Desktop or Downloads, macOS asks for permission. Because development builds aren't signed, macOS may ask again after each rebuild.

## Using her

| Do this | What happens |
| --- | --- |
| Click the halo, or press **⌥Space** | Opens or closes the chat |
| Drag the halo or the chat header | Moves her; she remembers where |
| **Esc** | Closes the chat |
| Menu bar icon | Open chat, put her away, hide or show her, reset her position, Launch at Login, quit |

### Changing her look

Click the palette button in the chat header to open her wardrobe. Every choice shows on her right away; **Save** keeps it (across restarts), **Cancel** puts the old look back, and **Original** resets everything.

| Part | Options |
|---|---|
| Color | Ember, Arc reactor, Toxic, Crimson, Void, Brass, Chrome, Sakura, or any custom color (she builds the darker metals and highlights from it) |
| Ring | 4 armor plates, 6 segments, 8 blades, vented band, twin crescents, spiked crown, floating shards, gyro rings |
| Plate pattern | Honeycomb, carbon weave, circuit traces, hazard stripes, dot grid, topographic, Greek key, brushed plain |
| Clamps | Bracket, talon claw, piston, arrow fin, round lug, twin prongs, rune tablet, none |
| Badges | Greek (Α Θ Σ Ω), Roman, runes, M I S A |

The **Eye** tab changes her eye on its own:

| Part | Options |
|---|---|
| Iris color | Match the shell, any theme color, or a custom color |
| Two-tone | Off, or a second color for the right half of the iris |
| Iris pattern | Fibers, rings, spiral, hex lens, starburst, reticle, circuit, nebula |
| Pupil | Aperture, cat slit, ring core, diamond, cross, star, hexagon, heart, triple dot |
| Center light | Match the iris, any theme color, or a custom color |

Every pupil still dilates, spins up when she's charged, and blinks. Eye parts live in `web/src/misa/eye-parts.tsx`.

The color recolors the chat and the menu-bar camera too. Parts live in `web/src/misa/skin.ts` (catalog) and `shell-parts.tsx` (geometry), so adding a new one is a single entry.

### Starting with your Mac

Check **Launch at Login** in the menu bar menu and she starts every time you log in, put away or on screen as you left her. Uncheck it to stop (it's also under System Settings > General > Login Items). macOS remembers the app's location, so keep it where it was when you turned this on, or turn it off and on again after moving it.

### Putting her away

When you don't need her on screen, put her away and she hangs from the menu bar.

- **Put away:** the ⤒ button in the chat header, "Put Away in Menu Bar" in the menu, saying "go away" or "put yourself away", or dragging her up into the menu bar.
- **Bring back:** click the camera, or press **⌥Space** to bring her back with the chat open. Right-click the camera for the menu.

She opens the chat toward the middle of the screen, so it works in any corner.

## Install

You need:

- macOS 14 (Sonoma) or newer
- Swift: Xcode, or Apple's free Command Line Tools (the installer offers to install them if they're missing)
- [Bun](https://bun.sh) or [Node.js](https://nodejs.org), to build the interface

```bash
git clone https://github.com/The-Hieusss/misa.git
cd misa
./install.sh
```

The script builds her from source on your Mac, puts `M.I.S.A..app` in `/Applications` (or `~/Applications`), and opens her. Building locally means macOS doesn't block her the way it blocks unsigned apps downloaded from the internet. Run it again any time to update after a `git pull`; it quits the running copy first.

Options: `INSTALL_DIR=~/Applications ./install.sh` to choose the folder, `OPEN=0` to skip opening her.

**Uninstall:** `./uninstall.sh` removes the app, her settings and her log. `KEEP_SETTINGS=1 ./uninstall.sh` keeps her look and position. Your files, `~/Screenshots` and `~/Disposable` are never touched.

### Building without installing

```bash
scripts/build.sh
open "build/M.I.S.A..app"
```

## How it's put together

```
web/   React + Vite + Tailwind: her look (MechaHalo from the portfolio), chat, animations
app/   Swift + AppKit: the floating window, dragging, ⌥Space, menu bar, brain
scripts/build.sh   builds web/, then app/, and bundles both into one .app
install.sh         checks the tools, runs the build, copies the app into Applications
```

- The web view only **asks** for things through a small set of messages (`web/src/bridge.ts`). Only the Swift side can act on the Mac.
- The built web files are served from inside the app at `misa://app/`, so nothing loads from the internet.
- `app/Sources/MISA/Brain.swift` routes requests to actions with keywords for now. Apple's on-device model will plug in there to choose actions.
- Each ability is one file in `app/Sources/MISA/Actions/`.

### Working on the look

```bash
cd web && bun run dev
```

This opens the interface in a normal browser with placeholder replies. To see changes inside the real app without rebuilding the web files:

```bash
MISA_DEV_URL=http://localhost:5173 "build/M.I.S.A..app/Contents/MacOS/MISA"
```

### Developer hooks

The running app listens for these system notifications, which are handy for testing:

- `app.misa.toggleChat`: open or close the chat
- `app.misa.toggleDock`: put her away or bring her back
- `app.misa.toggleLogin`: turn Launch at Login on or off
- `app.misa.inspect`: log what the page is showing
- `app.misa.snapshot`: save the web view to `$TMPDIR/misa-snapshot.png`
