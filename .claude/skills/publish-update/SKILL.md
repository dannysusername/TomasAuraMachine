---
name: publish-update
description: Build and publish a new version of TomasAuraMachine to GitHub so the installed app auto-updates. Use when asked to "update the package", "publish an update", "ship a release", "rebuild", or "cut a new version".
---

# Publish a TomasAuraMachine update

Ships a new version: bumps the version, builds the Windows package, creates a
GitHub Release, and updates the hosted `version.json` so every installed copy
prompts to auto-install. Run the steps **in order** — the release must exist
before `version.json` points at its download asset.

## Preconditions (check, don't assume)
- Working dir is the project root (`project.godot` present).
- `gh` is installed and authed as `dannysusername` (`gh auth status`).
- Godot binary at `/Applications/Godot.app/Contents/MacOS/Godot`.
- The change you're shipping is committed or staged — don't ship a dirty tree
  by accident; review `git status` first.

## Steps

### 1. Pick the version
Read the current `APP_VERSION` in [scripts/main.gd](../../../scripts/main.gd)
and `version` in [version.json](../../../version.json) (they must match). Bump to
the next version — default to a **minor** bump (`0.8.0` → `0.9.0`) unless the
user asks otherwise. Call it `vX.Y.Z` below.

### 2. Bump the version in code
Edit `APP_VERSION` in `scripts/main.gd` to the new `X.Y.Z` (no leading `v`).

### 3. Sanity-check the script parses
```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only --script scripts/main.gd
```
Exit 0 = good. Fix any parse errors before continuing.

### 4. Build + zip the Windows package
```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --export-release "Windows Desktop" build/windows/TomasAuraMachine.exe
cp bin/ffmpeg.exe build/windows/ffmpeg.exe          # ffmpeg ships beside the exe
rm -f build/TomasAuraMachine-windows.zip
( cd build/windows && zip -r -q ../TomasAuraMachine-windows.zip . )
```
Confirm `build/TomasAuraMachine-windows.zip` exists and is ~70+ MB.

### 5. Create the GitHub Release FIRST (with the zip asset)
```sh
gh release create vX.Y.Z build/TomasAuraMachine-windows.zip \
  --title "vX.Y.Z" --notes "<plain-language what's new, written for the user>"
```
Notes are user-facing (his brother reads them) — describe the benefit, not the
code. Verify the asset is live:
```sh
curl -s -o /dev/null -w "%{http_code}\n" -L \
  https://github.com/dannysusername/TomasAuraMachine/releases/download/vX.Y.Z/TomasAuraMachine-windows.zip
```
Must be `200` before the next step (the app's one-click installer downloads this).

### 6. Update version.json
Set all four fields in [version.json](../../../version.json):
- `version`: `X.Y.Z` (no `v`)
- `url`: leave as `…/releases/latest`
- `download`: `https://github.com/dannysusername/TomasAuraMachine/releases/download/vX.Y.Z/TomasAuraMachine-windows.zip`
- `notes`: short user-facing summary

### 7. Commit + push
```sh
git add version.json scripts/main.gd
git commit -m "vX.Y.Z: <short summary>"
git push
```
(Commit any code changes being shipped too, if not already committed.)

### 8. Verify the update is live
```sh
curl -s https://raw.githubusercontent.com/dannysusername/TomasAuraMachine/main/version.json
```
Confirm it shows the new `version` and `download`. Done — the installed app
checks this on next launch and prompts to auto-install.

## Notes & gotchas
- **Order matters:** release before `version.json`. If `download` 404s, the app
  falls back to opening the release page instead of one-click installing.
- Builds are **never committed** — only `version.json` + `scripts/main.gd` (and
  whatever code you're shipping). `build/`, `bin/`, `assets/` are gitignored.
- The build is produced on macOS but can only be *run* on Windows. The Windows
  file-swap auto-install path can't be verified from the Mac dev box.
- Keep `APP_VERSION` and `version.json`'s `version` in lockstep every release.
- Full background: [DISTRIBUTION.md](../../../DISTRIBUTION.md).
