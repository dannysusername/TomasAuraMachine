# TomasAuraMachine — virtual cinematography tool

Load a 3D model, fly a camera around it like a video game, hit Record, get a
playable video clip. Built with Godot 4.x + GDScript.

**Milestone 1 (this slice):** pick a `.glb` → free-fly with WASD + mouse →
Record → get a `.mp4` on disk.

## Controls (interactive window)
- **WASD** — move (relative to where you're looking)
- **Q / E** — move down / up
- **Hold right-mouse + move mouse** — look around
- **Shift** — move faster
- **Load Model (.glb)** button — pick a model from your computer
- **Record 5s Clip** button — frame a shot, then click to capture

## How recording works (so you know what to expect)
Godot's deterministic "Movie Maker" mode can only be switched on at launch, not
mid-run. So clicking Record launches a *second, hidden copy* of the app in movie
mode. That copy loads the same model, slowly orbits it for 5 seconds, writes an
AVI, and quits. Then the main app converts the AVI to MP4 with `bin/ffmpeg`.
The finished `.mp4` lands in the app's user-data folder, which pops open
automatically when it's done.

## Setup (do once)
1. Install **Godot 4.x** (Standard / GDScript build) — https://godotengine.org/download/macos/
2. Put **ffmpeg** in `bin/` — see [bin/README.md](bin/README.md), then run
   `chmod +x bin/ffmpeg`.
3. Open the project: launch Godot → **Import** → select this folder's
   `project.godot` → **Import & Edit**.
4. Press **F5** (or the ▶ Play button, top-right) to run.

## Project layout
- `project.godot` — Godot project config; main scene is `scenes/main.tscn`
- `scenes/main.tscn` — viewport, sky/lighting, camera, UI
- `scripts/main.gd` — app logic: model loading + the record/convert pipeline
- `scripts/fly_camera.gd` — the free-fly camera controller
- `bin/` — bundled ffmpeg binary
