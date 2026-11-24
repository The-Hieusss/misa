# M.I.S.A: Mac Internal Services Assistant

A floating assistant for macOS. She sits anywhere on your screen, above every app, and opens into a chat when you click her or press **⌥Space**. Everything runs on your Mac: no account, no API key, no subscription.

## Talk to her normally

With **Apple Intelligence** on (macOS 26), she understands plain English using Apple's on-device model. "Shove that PDF onto my desktop", "I need to grind for an hour", "throw Spotify out", "my disk is almost full" and "I'm turning this in for class" all work. Nothing you type leaves your Mac.

- Exact commands still go straight to her built-in actions, instantly. Only what they don't cover goes to the model.
- The model can only pick from the things she can actually do. Its choice runs through the same code as a typed command, so risky actions still show a confirm card. Quitting an app it picked asks you first.
- Greetings, thanks and quick questions get a short answer from the model.
- "Turn off the AI brain" goes back to exact commands only; "turn on the AI brain" brings it back; "is your AI brain on?" says whether it's running and why not.
- Without Apple Intelligence (or on macOS 14 and 15) she works as before, with exact commands.

## "Hey MISA"

Turn on **Listen for “Hey MISA”** in her menu bar menu (or say "start listening" in the chat), then say "Hey MISA" and what you need: "Hey MISA, mute my mic", "Hey MISA, find my resume". She opens the chat, shows what she hears, and answers like a typed request. "Hey MISA" on its own opens the chat and waits a few seconds for the request.

- It's off until you turn it on. The first time, macOS asks for the microphone and for speech recognition.
- Everything stays on your Mac: Apple's built-in sound classifier only checks whether someone is talking, and only then does on-device speech recognition look for her name. Nothing is sent anywhere.
- macOS shows its orange mic dot while she listens. She pauses while she's put away or hidden and while the screen is locked.
- "Stop listening" (typed or said) turns it off; "are you listening?" says whether she is.
- Apps can't use the low-power chip Siri listens on, so this uses a little more battery than "Hey Siri", mostly while people are talking nearby.

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
| Move or copy | "Move this to Desktop", "copy these to Documents", "put it in CHM 101", "move it to the Trash". Folders by name (Spotlight) or by path like `~/School/Spring`. Never overwrites: a clashing name gets a number. **Undo** puts things back |
| Mark disposable | Moves files to `~/Disposable` ([Disposable Downloads](https://github.com/The-Hieusss/disposable-downloads) trashes them on a timer) |

**Or ask her to:**

- start a focus timer: "focus for 25 min", "take a break", "pause", "how much time left". A ring around her halo counts down, and she chimes when it's done
- do math: "15% of $84.50", "18% tip on $64.20", "20% off $60", "sqrt(2) * 3". It uses a small parser that only understands numbers, operators and a few functions (like `safe_eval` in a calculator agent), so nothing is executed as code
- convert units: "3 cups in ml", "72 f to c", "how many oz in 2 lb", "10 gb in mb". Conversion factors come from Apple's `Measurement` API; cups and spoons are US measures
- tidy screenshots off your Desktop into `~/Screenshots/<year-month>/`, or trash ones older than 7 days
- save new screenshots to `~/Screenshots` instead of the Desktop
- tidy downloads older than 30 days (moves them to Disposable)
- move a file by name: "move Homework 6.pdf to Downloads". She finds it with Spotlight and asks which one if several match. Every move shows a confirm card first, and "undo" reverses the last one
- find files: "find my resume pdf", "where is homework 6", "find photos from last week", "find the zip I downloaded yesterday". Spotlight searches your home folder by name, narrowed by type (PDF, image, video, doc, slides, spreadsheet, folder, zip), date (today, yesterday, this/last week or month) and folder (Downloads, Desktop, Documents). If no name matches, she looks inside files. Results are numbered: "open 2", "show 3 in Finder" or "use 1"; a single result becomes "it", so "move it to Desktop" or "copy the text for AI" work next
- open apps: "open Claude", "launch Safari and Notes", "open vs code". She looks in Applications, Utilities and the system apps, and understands nicknames like "chrome", "settings" and "word"
- open websites: "open youtube.com", "go to github.com/apple", or sites she knows by name like "open gmail" or "open youtube and wikipedia" (an app with the same name wins). They open in your default browser
- search the web: "search for mac shortcuts", "google pomodoro technique", "search youtube for lofi beats"
- quit apps: "quit Spotify", "close Safari and Notes". Apps quit the normal way, so anything with unsaved work asks first. "Quit everything" lists the open apps on a confirm card first
- empty the Trash: "empty the trash", "take out the trash". She lists what's in it first and only empties it when you click the card. Finder does the emptying, so macOS asks once to let her control Finder
- show what's using your disk (read-only)
- calendar and reminders (the Mac's own Calendar and Reminders, so they sync to your iPhone through iCloud):
  - "what's on today", "what do I have tomorrow", "what's on my calendar this week", "what's next", "what are my reminders"
  - "remind me to submit HW 6 at 9pm", "remind me in 20 minutes to check the oven", "remind me to call mom tomorrow"
  - "add dentist to my calendar Friday at 3pm for an hour", "schedule study group next Tuesday 4-6pm"
  - "mark submit HW 6 done" (or "I finished the essay")
  - find one: "when is my dentist appointment", "what time is the CHM 101 exam"
  - change one: "move my dentist appointment to Friday at 4", "reschedule study group to next Monday", "push my meeting back 30 minutes", "move the exam earlier by an hour", "make the dentist appointment 2 hours long", "extend the meeting by 30 minutes", "rename dentist to dentist cleaning", "change the reminder to call mom to 7pm"
  - delete one: "cancel tomorrow's meeting", "delete the reminder to buy milk", "remove the dentist appointment from my calendar"
  - Every change and delete shows a confirm card first (deletes in red). For a repeating event only that one occurrence changes. If several match, she asks which, by day. Her notifications move or go away with it
  - New events and reminders show a confirm card first. Then **she sends her own notifications**: when a reminder is due (with **Done** and **Snooze 10 min** buttons) and 10 minutes before an event she added. macOS delivers them even when she isn't running. The first time, macOS asks for Calendars or Reminders access, and for notifications
- music in Spotify or Apple Music: "pause", "next song", "previous song", "what's playing", "shuffle on", "play my study playlist", "play lofi on spotify". Apple Music plays playlists and songs from your library by name; Spotify doesn't let other apps pick songs, so she opens Spotify's search for you. With neither open, play/pause and skip use the media keys (YouTube in a browser, Podcasts…). macOS asks once to let her control each app
- arrange windows: "put Safari on the left", "snap this to the right half", "top right corner", "left third", "make Notes full screen", "center this", "move this to the other screen", "Safari on the left and Notes on the right". "This" means the app you were using before you talked to her. Needs **Accessibility** permission (System Settings > Privacy & Security > Accessibility); because development builds aren't signed, macOS may ask again after she updates
- several things at once: "mute my mic and dim the screen, then focus for an hour". She runs each part in order and numbers the answers; a confirm card pauses the rest until you click it. A step that makes files hands them to the next ("convert to jpg and move it to Desktop")
- work Control Center:
  - volume: "volume 40", "turn it up", "volume down 10", "mute", "unmute", "what's the volume"
  - microphone: "mute my mic", "unmute my mic" (back to its old level)
  - brightness of the built-in screen: "brightness 70", "dim the screen", "brighter". macOS has no public brightness API, so she uses the one the brightness keys use (DisplayServices); external monitors aren't supported
  - sound devices: "switch output to AirPods", "use the MacBook Pro mic", "list sound devices"
  - Bluetooth: "connect to Home Speaker", "disconnect my headphones", "list bluetooth devices", "turn Bluetooth on". Only paired devices, matched by name; macOS asks once whether she may use Bluetooth. Turning Bluetooth off shows a confirm card, since a Bluetooth keyboard or mouse would stop working. AirPlay speakers (like a HomePod) can't be picked by apps; use Control Center > Sound for those
  - Do Not Disturb: "turn on do not disturb", "dnd off". macOS has no API for Focus, so the first time she makes two small Shortcuts ("MISA Do Not Disturb On" and "Off") and Shortcuts asks you to add them. She can't tell whether it's on
- show what's in Disposable, or "keep" a file from it

You can drag photos and videos straight from the Photos app too. She asks Photos for the original file (not the preview it also sends) and saves it to `~/Downloads/From Photos` first.

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
| Accessory | Something on her head: top hat, party hat, crown, flower, flower crown, bow, sprout, antenna, angel ring, propeller cap or cat ears. It sits on top of whichever shell she wears, leans with her, and hops when she spins; the flower and sprout sway, the antenna bobbles, the angel ring floats and the propeller spins |
| Shell | Armored ring, pyramid, cube, hex prism (an eye in every window), diamond (octahedron), dodeca (dodecahedron), sphere or geodesic. The solids are real 3D shapes: they lean toward the cursor, show their sides as they turn, spin a quarter turn and split apart while she thinks, and keep a window open where her eye looks out |
| Markings | Symbols engraved on a solid shell's faces: plain, Greek letters, Roman numerals, runes, kanji numerals or binary. A face without a window gets one large symbol; a face with a window gets small ones in its corners |
| Ring | 4 armor plates, 6 segments, 8 blades, vented band, twin crescents, spiked crown, floating shards, gyro rings, hex frame, sawblade, visor arc, petal plates, chain links, satellite pods, double tier, cross arms |
| Inner cog | The ring that spins inside her shell: classic teeth, honeycomb, carbon weave, circuit traces, hazard stripes, bearing dots, topographic, Greek key |
| Clamps | Bracket, talon claw, piston, arrow fin, round lug, twin prongs, rune tablet, crown, hammerhead, kite shield, pincer, turbine, ziggurat, spearhead, knuckles, none |
| Scanner | What sweeps around the dial between her eye and the plates: radar sweep, twin beams, quad beams, comet, loader arc, laser line, pulse rings, off |
| Arms | Claw, hydraulic, slim rods, arm blade, arm cannon, tentacle, magnet, or no arms |

Her **arms** are live: they sway and snap their claws when idle, the arm on your side reaches for the cursor, both come up when you hover over her, reach out wide when you drag files over her, and one waves when she has a message waiting. Click an arm and it waves back. While the chat is open they stay out (behind the chat), go to work while she replies, and snap when the answer lands. An arm hides when there's no screen room on its side. The empty space around her still clicks through to whatever is behind it. They live in `web/src/misa/mecha-arms.tsx`.

The **Eye** tab changes her eye on its own:

| Part | Options |
|---|---|
| Iris color | Match the shell, any theme color, or a custom color |
| Two-tone | Off, or a second color for the right half of the iris |
| Iris pattern | Fibers, rings, spiral, hex lens, starburst, reticle, circuit, nebula, triple tomoe, pinwheel, crest petals, ripple rings |
| Pupil | Aperture, cat slit, ring core, diamond, cross, star, hexagon, heart, triple dot, crescent, delta, keyhole, gear, clover, bolt, sparkle, goat bar, hourglass |
| Center light | Match the iris, any theme color, or a custom color |

Every pupil still dilates, spins up when she's charged, and blinks. Eye parts live in `web/src/misa/eye-parts.tsx`.

Ring, inner cog, clamps and scanner are parts of the armored ring, so picking one switches back to it. The solid shells live in `web/src/misa/solid-shell.tsx`.

The color recolors the chat and the menu-bar camera too. Parts live in `web/src/misa/skin.ts` (catalog) and `shell-parts.tsx` (geometry, including `CogArt`), so adding a new one is a single entry.

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
- Swift: Xcode, or Apple's free Command Line Tools (the installer offers to install them if they're missing). Either one builds everything, the AI brain included
- [Bun](https://bun.sh) or [Node.js](https://nodejs.org), to build the interface. If neither is installed, the installer offers to install Bun (with Homebrew when you have it)

```bash
git clone https://github.com/The-Hieusss/misa.git
cd misa
./install.sh
```

The script builds her from source on your Mac, puts `M.I.S.A..app` in `/Applications` (or `~/Applications`), and opens her. Building locally means macOS doesn't block her the way it blocks unsigned apps downloaded from the internet.

Keep the cloned `misa` folder where it is: she updates herself from it.

If the Swift build fails (for example with an older SDK), the build tries again without the AI brain, so she still installs and works with exact commands.

### Updating

She checks GitHub once a day. When there's a new version she says so in the chat (with the unread dot on her halo) and shows a macOS notification; the first time, macOS asks whether she may send notifications. Nothing is downloaded until you say so.

- **"Update yourself"** (or **"check for updates"**) lists what's new on a confirm card. Click **Update** and she runs `git pull` and `./install.sh` in her folder, restarts as the new version and tells you what changed. If the build fails she stays on the old version; the details are in `~/Library/Logs/misa-update.log`.
- **"What version are you?"** gives her commit and its date.
- **"Stop checking for updates"** / **"turn on update checks"** switches the daily check.

She won't pull over files you've edited in her folder, and she can't update a copy installed from a ZIP download. In either case, or for a copy installed before self-updating existed, update by hand: `git pull`, then `./install.sh`.

Options: `INSTALL_DIR=~/Applications ./install.sh` to choose the folder, `OPEN=0` to skip opening her.

**Uninstall:** `./uninstall.sh` removes the app, her settings and her log. `KEEP_SETTINGS=1 ./uninstall.sh` keeps her look and position. Your files, `~/Screenshots` and `~/Disposable` are never touched.

### Building without installing

```bash
scripts/build.sh
open ~/Library/Caches/app.misa.build/M.I.S.A..app
```

The app is put together and signed in `~/Library/Caches/app.misa.build/`, outside the repo: if the repo is in iCloud Drive (a synced Desktop or Documents folder), iCloud tags new files and code signing fails now and then. `build/M.I.S.A..app` is a copy for convenience.

## How it's put together

```
web/   React + Vite + Tailwind: her look (MechaHalo from the portfolio), chat, animations
app/   Swift + AppKit: the floating window, dragging, ⌥Space, menu bar, brain
scripts/build.sh   builds web/, then app/, and bundles both into one .app
install.sh         checks the tools, runs the build, copies the app into Applications
                   (also what she runs to update herself, from app/Sources/MISA/Actions/Updater.swift)
```

- The web view only **asks** for things through a small set of messages (`web/src/bridge.ts`). Only the Swift side can act on the Mac.
- The built web files are served from inside the app at `misa://app/`, so nothing loads from the internet.
- `app/Sources/MISA/Brain.swift` routes requests to actions with keywords. Anything it doesn't recognize goes to `AIBrain.swift`, where Apple's on-device model (Foundation Models, guided generation) fills in a typed `Intent`. Its schema is built in code (`DynamicGenerationSchema`) rather than with the `@Generable` macro, because that macro's compiler plugin only ships with Xcode. That intent becomes a plain command for the same router. The framework is weak-linked, so the app still runs on macOS 14 and 15.
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
