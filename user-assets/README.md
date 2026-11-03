# user-assets

Copy of the media hand-picked for the Mac version of Nimbus, kept here so the Windows/Steam port
can reuse it. Copied from `~/Library/Application Support/Nimbus/`; nothing in the app reads this folder.

- `music/` — ambient menu music (looped on the home screen)
- `themes/<gameID>.mp3` — per-game theme song played when that game is focused; `volume.json` holds per-game volume
- `custom/<gameID>/` — per-game overrides: `bg.*` background, `card.*` shelf cover art, `logo.*` title logo; `mute.json` holds per-game video mute
- `manifest.json` — gameID → title + Steam app ID, so the port can re-key everything to Steam appids

Game IDs are GeForce NOW cmsIds, not Steam appids.
