# How to use TomasAuraMachine

A simple tool to turn a 3D model into a video clip: load a model, move a camera
around it, hit Record, get a video. This file is kept up to date as features are
added — check the date below.

_Last updated: 2026-06-20 (drag-and-drop + sample)_

---

## Opening the app (for now, during development)
1. Open **Godot** → the **TomasAuraMachine** project.
2. Press **F5** (or the ▶ Play button, top-right) to run it.
3. A window opens — that's the app. (When it's packaged as a Windows `.exe`
   later, your brother will just double-click it instead.)

> If a change was just made and you don't see it, **close the game window and
> press F5 again** — you don't need to reopen the whole editor.

## 1. Load a model
Three ways — whichever is easiest:
- **Drag a `.glb` file onto the window** (simplest).
- Click **Load Model (.glb)** and pick a `.glb` or `.gltf` file.
- Click **Try a Sample** to instantly load a built-in shape — no download needed,
  great for a first try.

The camera automatically frames whatever you load so it's centered and visible.

Don't have a model? Get free ones at **polyhaven.com/models** (choose the **GLB**
format) or **sketchfab.com** (free + downloadable). If you drop something that
won't work (a `.blend`, `.fbx`, or `.zip`), the app tells you in plain language.

## 2. Move the camera

**Orbit mode (default — the easy one):**
- **Left-drag** — spin around the model
- **Scroll wheel** — zoom in / out
- **Right-drag** — pan (slide the view)

**Free-fly mode (advanced):** click **Switch to Free-fly** or press **Tab**.
- **WASD** — move where you're looking
- **Q / E** — down / up
- **Hold right-mouse** — look around
- **Shift** — move faster

The hint line in the top-left always shows the controls for your current mode.

## 3. Record your shot
The app records **the camera movement you actually perform** — so the shot you
fly *is* the shot you get.

1. Click **● Record** to start. A red **● REC** counter appears.
2. Now move the camera however you want — orbit around, push in, fly past. Take
   your time; the clip is exactly as long as you record.
3. Click **■ Stop** when you're done.
4. A window briefly flashes (it re-renders your exact movement cleanly), then a
   **"Your clip is ready!"** popup appears with two buttons:
   - **▶ Watch** — play the video right away
   - **📁 Open Folder** — show it in your files

> Tip: plan your move before hitting Record, like a real camera operator. You
> can record as many takes as you like — each one saves a separate video.

## Where the videos go
Every clip is saved to a **TomasMovies** folder on your **Desktop**, with a
name like `shot_2026-06-20_22-05-13.mp4` (the date and time). Easy to find, and
ready to drop into any video editor.

## Something broke?
Just say so — the errors are written to logs that can be read directly, so you
don't need to copy anything. Describe what you did and what happened.
