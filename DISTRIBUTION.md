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
  "version": "0.7.0",
  "url": "https://github.com/dannysusername/TomasAuraMachine/releases/latest",
  "download": "https://github.com/dannysusername/TomasAuraMachine/releases/download/v0.7.0/TomasAuraMachine-windows.zip",
  "notes": "What's new in this version."
}
```

- `download` is the **direct .zip URL** for one-click auto-install (Windows). It
  must point at the matching release's asset, so **create the release first**,
  then publish `version.json`. If `download` is missing, the app falls back to
  opening `url` (the release page).

### Where to host it (pick one)
- **GitHub Releases (recommended, free):** create a repo, publish each build as a
  Release, and keep `version.json` as a file in the repo. The app reads the raw
  URL (`https://raw.githubusercontent.com/<you>/<repo>/main/version.json`) and the
  `url` points at the release's download. Bonus: a free, stable home for builds.
- **A cloud drive direct link** (Dropbox/Drive) or **any static website**: also
  fine — just needs a stable URL the app can fetch.

## Live setup (GitHub — configured ✓)
- Repo: https://github.com/dannysusername/TomasAuraMachine (public)
- The app checks: `https://raw.githubusercontent.com/dannysusername/TomasAuraMachine/main/version.json`
  (this URL is baked into `UPDATE_CHECK_URL` in `scripts/main.gd`).
- Builds are published as **GitHub Releases**; `version.json`'s `url` points at
  `…/releases/latest`, so the Download button always opens the newest release.

## Publishing a new version (the routine)
1. Make your changes.
2. Bump `APP_VERSION` in `scripts/main.gd` (e.g. `0.1.0` → `0.2.0`).
3. Rebuild + re-zip (see "Rebuild the Windows package" below).
4. Publish the release FIRST, then update `version.json` (incl. the `download`
   URL for the new tag) and push:
   ```sh
   gh release create v0.8.0 build/TomasAuraMachine-windows.zip \
     --title "v0.8.0" --notes "What changed."
   # edit version.json -> version, notes, and download = .../download/v0.8.0/TomasAuraMachine-windows.zip
   git add version.json scripts/main.gd && git commit -m "Release v0.8.0" && git push
   ```
5. Next time your brother opens the app, it sees the newer version and prompts him.

> In practice: just tell the assistant "publish an update" and it runs all of this.

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
