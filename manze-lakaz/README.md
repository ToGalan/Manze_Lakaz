# Manze Lakaz

A digital hidden-information card game built in Godot 4.7, playable hot-seat
or online (WebRTC peer-to-peer via the [Tube](https://github.com/koopmyers/tube)
addon, no server to host).

## Web export (itch.io)

The project ships an HTML5 "Web" export preset (`export_presets.cfg`)
configured specifically for itch.io:

- **Renderer: Compatibility** (`renderer/rendering_method="gl_compatibility"`
  in `project.godot`). Web exports run on WebGL 2.0, which the Forward+ and
  Mobile renderers cannot target -- only Compatibility can.
- **Single-threaded** (`variant/thread_support=false` in the preset).
  Threaded Web builds require SharedArrayBuffer, which needs COOP/COEP
  response headers. itch.io has a checkbox for that, but turning it on
  causes real problems for players: Firefox blocks downloads on the page,
  the itch desktop app renders a blank white screen, and iOS/macOS can fail
  to load the game at all. This is a turn-based card game with no threaded
  workload, so there's nothing to gain from threads and a lot to lose --
  export single-threaded and leave that checkbox off.
- Dev-only content (`tests/`, `sim/`) is excluded from the exported package
  via the preset's `exclude_filter`; neither is referenced by the shipped
  game. Tube's `addons/tube/inspector/` debugging tool is NOT excluded --
  `ui/GameScreen.gd` instances `tube_inspector.tscn` at runtime (hidden
  behind the Debug toggle) so WebRTC connection state is diagnosable in a
  built game, not just the editor.

### Building

```powershell
./build_web.ps1
```

This exports the "Web" preset to `build/web/`, then zips its *contents*
(not the folder itself) to `build/manze-lakaz-web.zip`, with `index.html`
at the root of the archive -- itch.io requires that exact layout, or the
game fails to load after upload. Pass `-GodotExe <path>` if your Godot
install isn't at the default path baked into the script.

If you'd rather run the steps by hand:

```powershell
godot --headless --path . --export-release "Web" "build/web/index.html"
# then zip the *contents* of build/web/ (not the build/web folder itself)
# into a zip with index.html at the archive root.
```

### Uploading to itch.io

1. Upload `build/manze-lakaz-web.zip` as a new file on the project's edit page.
2. Check **"This file will be played in the browser"** on that upload.
3. Leave **"SharedArrayBuffer support"** (the COOP/COEP headers checkbox)
   **unchecked** -- this build is single-threaded and doesn't need it;
   enabling it anyway only adds the Firefox/itch-app/iOS problems above
   with no upside.

### Local testing during development

A "Web" export preset with **Run in Browser** enabled is configured in
`export_presets.cfg`, so the editor's run bar can launch the game in your
default browser directly -- no manual export needed while iterating.

## Hot-seat / bot testing

`tests/run_tests.gd` and `sim/run_sim.gd` are headless-only tools and are
never bundled into the exported game (see `exclude_filter` above):

```powershell
godot --headless --path . --script res://tests/run_tests.gd --quit
godot --headless --script res://sim/run_sim.gd -- --games=2000
```
