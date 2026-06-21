# How to use TomasAuraMachine

A simple tool to turn a 3D model into a video clip: load a model, move a camera
around it, hit Record, get a video. This file is kept up to date as features are
added — check the date below.

_Last updated: 2026-06-20 (piloting / moving models)_

---

## Opening the app (for now, during development)
1. Open **Godot** → the **TomasAuraMachine** project.
2. Press **F5** (or the ▶ Play button, top-right) to run it.
3. A window opens — that's the app. (When it's packaged as a Windows `.exe`
   later, your brother will just double-click it instead.)

> If a change was just made and you don't see it, **close the game window and
> press F5 again** — you don't need to reopen the whole editor.

## 1. Add models to the scene
You can load **several models at once** to build a scene (e.g. terrain + two
jets). Three ways to add one — whichever is easiest:
- **Drag a `.glb` file onto the window** (simplest).
- Click **Add Model (.glb)** and pick a `.glb` or `.gltf` file.
- Click **Try a Sample** to instantly add a built-in shape — no download needed.

Each model you add appears in the **Scene** list on the right. There you can:
- **Click a model's name** to select it.
- **Click ✕** to remove it from the scene.

The camera automatically reframes so everything in the scene is visible. When
you record, **all** models in the scene appear in the video.

## 2. Arrange the scene (move models where you want)
New models appear at the center, so they may overlap at first. To position one:
1. Click its name in the **Scene** list to select it.
2. Click **Place Selected**. A placement bar appears at the bottom.
3. Now position it:
   - **Drag** it across the floor to move it around.
   - **Scroll wheel** to raise / lower it (e.g. lift a jet into the sky).
   - **⟲ Turn / Turn ⟳** to spin it (or hold **A** / **D**).
   - Hold **W** / **S** to tilt it (point a jet's nose up/down).
   - **− Smaller / + Bigger** to resize it (or **[** / **]**).
   - **⤓ Drop to floor** to rest it on the ground.
4. Click **✓ Done** when it's where you want.

Repeat for each model to stage your scene (e.g. terrain on the floor, jets up in
the air).

Don't have a model? Get free ones at **polyhaven.com/models** (choose the **GLB**
format) or **sketchfab.com** (free + downloadable). If you drop something that
won't work (a `.blend`, `.fbx`, or `.zip`), the app tells you in plain language.

## 3. Make a model move (pilot it)
You make things move by **flying them yourself and recording it** — like a
remote-control plane. Do one model at a time.

1. Select a model in the **Scene** list, then click **Pilot Selected**.
2. The camera follows behind it. Fly it:
   - **WASD** — fly forward/back/left/right
   - **Hold right-mouse + move** — steer (turn / point the nose)
   - **Q / E** — down / up, **Shift** — faster
3. When ready, click **● Record flight**, fly your path, then **■ Stop**. That
   model now remembers that flight.
4. Click **✓ Done**.

Repeat for the next model. **While you pilot one, any models you've already
recorded will fly their paths too** — so you can chase or dodge them (perfect for
a dogfight: record jet 1, then fly jet 2 chasing it).

Click **▶ Play scene** any time to watch everything move together. (Models with
no recorded flight just stay where you placed them.)

## 4. Move the camera

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

## 5. Record your shot
The app records **the camera movement you actually perform** — so the shot you
fly *is* the shot you get. **Any models with recorded flights fly during your
shot**, so you film the action live.

1. Click **● Record** to start. A red **● REC** counter appears, and your moving
   models begin their flights.
2. Now move the camera to follow the action — orbit around, push in, fly past.
   The clip is exactly as long as you record.
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
