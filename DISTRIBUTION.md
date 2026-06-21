# Distributing the app & shipping updates

This is the **developer** guide (for you, not your brother). It covers how the
in-app update check works and how to publish a new version.

## How the in-app update check works
- The app has a version baked in: `APP_VERSION` in `scripts/main.gd`.
- On launch it quietly fetches a small JSON file from `UPDATE_CHECK_URL`
  (also in `scripts/main.gd`).
- If the hosted `version` is newer, the app shows an "Update available" popup
  with a **Download** button that opens the `url` from the JSON.
- If there's no internet, the URL is empty, or the version isn't newer, the user
  sees nothing. It never nags.

### The hosted file (`version.json`)
Host this anywhere with a stable public URL, then paste that URL into
`UPDATE_CHECK_URL`:

```json
{
  "version": "0.2.0",
  "url": "https://example.com/download/TomasAuraMachine-0.2.0.zip",
  "notes": "What's new in this version."
}
```

### Where to host it (pick one)
- **GitHub Releases (recommended, free):** create a repo, publish each build as a
  Release, and keep `version.json` as a file in the repo. The app reads the raw
  URL (`https://raw.githubusercontent.com/<you>/<repo>/main/version.json`) and the
  `url` points at the release's download. Bonus: a free, stable home for builds.
- **A cloud drive direct link** (Dropbox/Drive) or **any static website**: also
  fine — just needs a stable URL the app can fetch.

## Publishing a new version (the routine)
1. Make your changes.
2. Bump `APP_VERSION` in `scripts/main.gd` (e.g. `0.1.0` → `0.2.0`).
3. Export the Windows build (see below) and zip it **with `ffmpeg.exe` inside**.
4. Upload that zip to your host.
5. Update `version.json` (`version`, `url`, `notes`) and upload it.
6. Next time your brother opens the app, he gets the update prompt.

## Windows export (configured ✓)
Set up and working. The pieces:
- `export_presets.cfg` — a "Windows Desktop" preset, x86_64, with the `.pck`
  embedded into the `.exe` (single-file app). It excludes `bin/`, `assets/`,
  `memory/`, and `*.md` from the build to keep it lean.
- `bin/ffmpeg.exe` — the Windows ffmpeg, shipped **next to** the `.exe` (the app
  looks there first; inside an exported build `res://bin` isn't a real folder).

### Rebuild the Windows package
From the project folder:
```sh
# 1. (after bumping APP_VERSION in scripts/main.gd)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --export-release "Windows Desktop" build/windows/TomasAuraMachine.exe

# 2. make sure ffmpeg.exe is beside it
cp bin/ffmpeg.exe build/windows/ffmpeg.exe

# 3. zip it for sharing
( cd build/windows && zip -r -q ../TomasAuraMachine-windows.zip . )
```
The result is `build/TomasAuraMachine-windows.zip` — the single thing you share.

> Note: the build is produced on macOS but can only be *run/tested* on Windows.
> Always do a quick launch test on a Windows PC before sharing widely.
