# Starfall — Commander Whiskers

The **color version** of Starfall: a fast side-scrolling arcade shooter for the ClockworkPi uConsole, Omarchy and macOS, built with LÖVE 11.5 and Lua.

Fly through three sectors and defeat the three-phase Dreadnought. Collect shields, piercing ion lasers, prism shots, homing rockets, mega blasters, nitro and overdrive. Dash through danger, clear hostile fire with nova bombs, and build a score multiplier through kills and near misses. Layered parallax, banked ship sprites and a small vulnerable core keep the action readable.

## Install on Omarchy or macOS

Download and unzip this repository, or clone it:

```sh
git clone https://github.com/cosmindolha/starfall.git
cd starfall
./tools/install.sh
```

- **Omarchy / Arch Linux:** installs the LÖVE runtime if needed, adds Starfall to the application menu, and installs a `starfall` command. On Wayland, the launcher temporarily suspends conflicting uConsole gamepad handlers and restores them when the game exits.
- **macOS:** installs `Starfall.app` in `~/Applications`, using the official LÖVE 11.5 runtime. Open Starfall from Finder. The installer does not launch the game automatically.

macOS uses its built-in archive tools; Omarchy uses Python 3 for packaging. Run `./tools/install.sh --help` for installation options. Art applications and generation services are not needed.

## Play directly

With LÖVE 11.5 installed, run from the project directory:

```sh
love .
```

On macOS, you can also double-click **Run Starfall.command** with `love.app` installed in `/Applications` or `~/Applications`. For another installation, set `STARFALL_LOVE` to its executable, or put that executable's path on one line in `.starfall-love` (ignored by Git).

| Action | uConsole pad | Keyboard |
|---|---|---|
| Move | D-pad | Arrows / WASD |
| Fire | A | Space / Z |
| Secondary weapon | Y | V |
| Dash | X | X |
| Nova bomb | B | C |
| Precision movement / core marker | Y | Shift |
| Pause / resume | Esc | Esc |
| Deploy / select | A | Enter |
| Menu back | B | Esc |
| Fullscreen | Options | F11 |

Hold Fire for continuous shots. Y combines secondary fire with precision movement; keyboard V fires independently of Shift. Rocket and mega ammunition are separate, and the game switches to the other stocked heavy weapon when one runs out. Shields absorb hits before hull damage. Nitro boosts movement and scrolling for eight seconds; Overdrive accelerates fire for ten seconds.

The Controls menu supports keyboard remapping. Options save music/SFX volume, screen shake and fullscreen settings. Losing focus pauses a manual flight.

## How it was built

Cosmin directed the game and visual style; Codex implemented the Lua game, connected the local creative tools, and iterated through simulation tests and playable builds. This was a small asset pipeline: create the art offline, validate it, then ship ordinary images and audio that the game can load quickly.

### Resources used

| Resource | What it did in this game |
|---|---|
| [LÖVE 11.5](https://love2d.org/) + Lua | Game loop, rendering, input, audio and portable runtime |
| [Blender](https://www.blender.org/) | Original ship geometry, lighting and bank-angle renders |
| [Pixelization-CoreML](https://huggingface.co/mlboydaisuke/Pixelization-CoreML) | Local pixel-style processing of the Blender renders |
| [PixelLab API](https://www.pixellab.ai/pixellab-api) | Pixel-art planet and asteroid generation |
| [OpenAI image generation](https://developers.openai.com/api/docs/guides/image-generation) through Codex | The final nebula background |
| [Pillow](https://pillow.readthedocs.io/en/stable/) | Palette processing, alpha preservation and sprite-atlas packing |
| Playdate Forge Sound Lab / `pdforge` | Custom local Swift tool used to synthesize the sound effects |
| [FFmpeg](https://ffmpeg.org/) | Soundtrack conversion and audio validation |
| Rajdhani + Share Tech Mono | HUD and menu fonts; bundled OFL notices |

The custom studio applications, their credentials and their generation tools are not part of this repository. All finished images and sounds needed to play are already in `assets/`.

### 1. Establish a readable style

The reference moodboard used retro science-fiction silhouettes: rib cages, crescents, long prows and alien cathedral-like shapes. A dark navy/indigo background leaves room for cyan player weapons, violet enemy armor and warm hostile projectiles. Gameplay objects need clear silhouettes at their final on-screen size; a beautiful full-size image can still fail as a tiny sprite.

### 2. Build ships in Blender, then render real bank views

Seven original procedural models were built from hull sections, extruded wings, cylinders, rib struts and curved crescent blades. A fixed orthographic camera and shared lighting kept the views consistent.

The player has five bank angles; five ordinary enemy types and the boss each have three. Those **23 frames** come from rotating the 3D models around their longitudinal axes. The highlights and silhouettes change with the bank, giving a 2D sprite real depth. Ordinary ships were rendered at 1024×768 and the boss at 2048×1536 before conversion.

### 3. Apply the pixel style without damaging transparency

The render was fitted into a 512×512 input for the local Core ML model, then returned to the atlas cell size. The model produces RGB, so the original Blender alpha channel was restored afterward and checked byte-for-byte against the resized source alpha.

Shared palettes kept each bank consistent: 64 colors for the player and 96 for the alien fleet. The player's original hue and saturation were preserved while the model supplied bounded luminance changes. This helped prevent the pixel pass from turning the cyan/pearl player into a differently colored ship. Transparent RGB was cleared to prevent atlas-edge bleed.

The model is labelled for non-commercial research use; see [its model card](https://huggingface.co/mlboydaisuke/Pixelization-CoreML) and [ASSETS.md](ASSETS.md).

### 4. Generate backgrounds with the gameplay in mind

PixelLab generated the ringed planet and asteroid. Codex's image generator supplied the final cinematic nebula. The prompts requested restrained contrast, dark edges, no text or interface, and enough empty space for the action. Foreground objects were generated with transparent backgrounds and margin around their silhouettes.

A useful prompt pattern is: **object + camera angle + pixel style + palette + silhouette requirements + exclusions**. For a background, also state where the playable empty space should be. Review the result at actual game size before accepting it.

These assets are separate layers. Scrolling offsets are integrated over time, so nitro and dash can accelerate parallax without snapping the background to a new position.

### 5. Synthesize short, repeatable arcade sounds

The local `pdforge` Sound Lab generated seventeen effects from seeded procedural patches: pulse/ion/prism fire, rocket ignition, mega discharge, shield hits, explosions, pickups, nitro, menus and warnings. The patches combine oscillator or noise waveforms with pitch sweeps, envelopes, filtering and restrained bit crushing.

Rapid-fire sounds are short and quiet enough to overlap. The exports were checked for non-silence, headroom and repeatable hashes, then saved as mono PCM WAV files. LÖVE uses pooled sources and throttles repeated effects. The supplied *Commander Whiskers* music was converted to stereo Ogg Vorbis and streamed rather than loaded completely into memory.

### 6. Pack and validate the finished game

The ship frames share one **2048×1024 RGBA atlas**. Ordinary cells are 256×192; the boss cells are 512×384. [`assets/images/ships.lua`](assets/images/ships.lua) records frame rectangles, pivots and scale. Packing checks ensured that rectangles did not overlap and silhouettes stayed clear of cell edges.

The fixed-step simulation is separate from rendering, making it testable without the graphics engine. The 49 regression tests cover collisions, terminal states, weapon modes, pickups, homing and input/remapping behavior. An optional controller then flies a real rendered build through the full campaign using ordinary controls.

To build something similar, follow the same sequence: choose a readable style, render consistent views, process and inspect the pixels, preserve alpha, pack the atlas, integrate effects, and test the actual game. Keep expensive generation outside the runtime; the installed game needs only its engine and finished assets.

## Build

The checked-in assets are ready to play. Python 3 packages the runtime:

```sh
python3 tools/package_game.py
love dist/starfall.love
```

The deterministic `.love` bundle contains only game code, runtime assets and asset notices. `dist/manifest.json` records each packaged file's SHA-256 hash.

## Verify

With Lua installed:

```sh
lua tests/sim_spec.lua
lua tests/arsenal_spec.lua
lua tests/review_spec.lua
lua tests/upgrade_review_spec.lua
```

The optional test controller uses ordinary game inputs and does not change damage, health or timers:

```sh
love dist/starfall.love --mute --test-autoplay --test-speed=4 --test-duration=59
```

Gameplay uses 640×360 logical coordinates, a fixed 60 Hz simulation and a 1280×720 render canvas. Ship bank views share one atlas. The soundtrack streams from the included Ogg file.

This repository contains the color game only. Art applications, models, generation tools, local deployment settings, reference videos and the separate monochrome game are excluded. See [ASSETS.md](ASSETS.md) for asset provenance and font notices.
