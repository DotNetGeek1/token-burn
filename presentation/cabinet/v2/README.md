# Burn Cabinet v2 art kit

Layered, style-locked art for the responsive cabinet (plan: *Burn Cabinet v2*,
section 3). Every picture here was generated with the Cursor `GenerateImage`
tool from `tools/asset_generator/reference/cabinet_plate.png` (the retired
painted plate, kept only as the style reference) as the style reference and
then post-processed by `tools/asset_generator/cabinet_v2_post.py`. Geometry is
never read from these pictures: 9-slice frames stretch around live containers,
tiles sit on mounts positioned by `presentation/cabinet_layout_profiles.json`.

Registered in `presentation/asset_catalog.json` under `cabinet_v2`, read
through `AssetCatalog.cabinet_v2_texture()`, `cabinet_v2_frame()`,
`cabinet_commit_texture()` and `cabinet_system_tile()`.

`_raw/` holds the accepted generator output (with a `.gdignore` so Godot never
imports it) plus `contact_sheet.png`, the review sheet of every final asset.

## Final assets

| File | Size | Notes |
| --- | --- | --- |
| `chassis_backdrop.png` | 1920x1080 | Opaque decorative wall; cover-crop behind the machine. |
| `maintenance_wall.png` | 1920x1080 | Opaque workshop wall/floor, empty centre. |
| `crt_bezel.png` | 1536x864 | 9-slice, opening knocked to alpha. Margins `[110,110,110,120]` (frame itself is ~52 px, 67 px at the bottom). |
| `telemetry_frame.png` | 768x1024 | 9-slice, opening knocked to alpha. Margins `[72,72,72,80]` (frame ~29 px). |
| `deck_plate.png` | 1536x864 | 9-slice, opaque. Margins `[96,96,96,96]`. |
| `backplane_rail.png` | 1536x864 | 9-slice, opaque, vent slots. Margins `[96,96,96,96]`. |
| `panel_9slice.png` | 1024x768 | 9-slice, opaque. Margins `[64,64,64,64]`. |
| `commit_idle.png` `commit_armed.png` `commit_danger.png` `commit_busy.png` | 960x400 each | Background knocked to alpha; the housing is ~815x400 centred (aspect ~2.05:1). |
| `abort_lever_channel.png` | 585x1040 | 9:16 plate, slot knocked to alpha. Slot rect as a fraction of the plate: `[0.431, 0.072, 0.135, 0.855]` (also in the catalog as `lever.channel_slot`). |
| `abort_lever_handle.png` | 320x320 | Handle on alpha, ~108 px wide x 320 tall, centred. |
| `bay_shutter.png` | 640x382 | Opaque; same aspect as `module_bay_frame.png`. |
| `systems/<system>_t1..t4.png` | 480x480 each | compute, cooling, power, backplane, control. Plate on alpha, all four tiers of a system cut to one plate size. |

Deviation from the brief: the lever channel was specified as "~360x1040"; the
generator's 9:16 plate is kept whole at 585x1040 because cropping to 360 wide
would have cut the corner brackets off. Consumers fit the texture by height.

## Shared prompt preamble (used verbatim in every call)

```
Photoreal game UI asset, front-on orthographic camera, even key light from the
top-left. Materials: weathered rust-brown steel with rivets and scorched edges,
amber stencil paint (#EDAD3D), phosphor green glass (#6BEB99), red (#EB4738)
used only for the commit/danger element, near-black steel (#151616). Pure flat
black (#000000) wherever an opening or the background must be knocked out. NO
text, NO numbers, NO letters, NO logos anywhere. Match the material, weathering
and finish of the reference cabinet plate exactly.
```

Every call passed `reference_image_paths=[tools/asset_generator/reference/cabinet_plate.png]`;
family follow-ups also passed the first accepted piece of that family (noted
below). Generator output sizes: 16:9 -> 1280x720, 4:3 -> 1152x864,
3:4 -> 864x1152, 9:16 -> 720x1280, 1:1 -> 1024x1024.

## Per-asset prompts (appended to the preamble)

**chassis_backdrop** (16:9, plate only) — accepted on the second attempt; the
first carried a red lever and an emblem copied from the plate.
> ASSET: chassis backdrop. A full-frame decorative wall of dark industrial machinery that surrounds an arcade machine: overlapping riveted steel panels, thick bundled cable looms, corrugated hoses, pipes with flanges, small vents and grilles, a few faint amber stencil hazard stripes. Dark, low-contrast, mostly near-black steel and rust so it sits quietly behind UI. STRICTLY NO screens, NO monitors, NO buttons, NO levers, NO switches, NO handles, NO emblems, NO crests, NO badges, NO logos, NO glowing lights, NO red parts, NO text. Purely passive structure: panels, rivets, pipes, cables, vents. The whole frame is filled edge to edge with the wall; there is no machine or focal object in the centre, just denser panels and cables.

**crt_bezel** (16:9, plate only) — family anchor for all frames.
> ASSET: CRT bezel frame for 9-slice scaling. A thick riveted dark steel monitor bezel filling the whole canvas, about 110 pixels thick on all four sides, with a large rectangular opening in the middle that has gently rounded inner corners. The opening is PURE FLAT BLACK (#000000) with no reflections, no glass, no gradient. The frame is uniform along each edge (no unique decorations mid-edge) so it can be stretched: evenly spaced rivets along the rails, scorched rust at the outer edge, a thin amber stencil hairline around the inner lip. The frame fills the canvas to the very edges; there is nothing outside the frame.

**telemetry_frame** (3:4, plate + crt_bezel)
> ASSET: telemetry instrument frame for 9-slice scaling, same family and finish as the second reference image (the CRT bezel). A tall portrait narrow riveted dark steel instrument frame filling the whole canvas, about 72 pixels thick on all four sides, with a large rectangular opening in the middle with slightly rounded inner corners. The opening is PURE FLAT BLACK (#000000) with no reflections, no glass, no gradient. The frame is uniform along each edge so it can be stretched: evenly spaced small rivets along the rails, scorched rust at the outer edge, a thin machined bevel around the inner lip. The frame fills the canvas to the very edges; nothing outside the frame.

**deck_plate** (16:9, plate + crt_bezel)
> ASSET: command deck plate for 9-slice scaling, same family and finish as the second reference image (the CRT bezel). A flat, fully opaque riveted dark steel deck plate filling the entire canvas edge to edge, NO opening, NO hole, NO screen. A raised bevelled border about 96 pixels wide runs around the outside with evenly spaced rivets; the interior is a flat plain brushed dark steel surface with light rust speckle and a few faint scorch marks, uniform enough to be stretched. No buttons, no switches, no controls, no text. Everything is steel; no black areas.

**backplane_rail** (16:9, plate + crt_bezel)
> ASSET: backplane rail for 9-slice scaling, same family and finish as the second reference image (the CRT bezel). A fully opaque dark near-black steel backplane panel filling the entire canvas edge to edge, NO opening, NO hole. A riveted raised rail border about 96 pixels wide around the outside; the interior is a flat dark steel surface with rows of subtle narrow horizontal vent slots (shallow, dark grey, not pure black) and light rust speckle, uniform enough to be stretched. No buttons, no cartridges, no bays, no lights, no text. No pure black areas.

**panel_9slice** (4:3, plate + crt_bezel)
> ASSET: generic panel for 9-slice scaling, same family and finish as the second reference image (the CRT bezel). A fully opaque dark steel panel filling the entire canvas edge to edge, NO opening, NO hole. A simple thin bevelled steel border about 64 pixels wide with one rivet in each corner only; the interior is a plain flat dark charcoal steel surface with very light rust speckle, uniform enough to be stretched. No buttons, no lights, no text, no decorations in the middle. No pure black areas.

**commit_button_states** (16:9, plate only) — accepted on the second attempt;
the first baked IDLE / ARMED / DANGER / BUSY nameplates into the housings.
> ASSET: commit button state sheet. On a PURE FLAT BLACK (#000000) background, a precise 2x2 grid of four copies of the SAME wide rectangular arcade commit button (aspect about 2.4:1: a rounded riveted steel housing holding a wide glass cap, like the red button on the reference plate). All four housings are identical in size and shape and are centred in their quadrants with generous black margin between them. The housing has NO label plate, NO nameplate, NO engraving, NO writing of any kind: the housing is just the steel frame around the cap. Top-left: the cap is hidden behind a closed dark smoked-steel roller shutter with fine horizontal slats, no glow. Top-right: the cap is bright glowing red (#EB4738) glass with a soft inner glow. Bottom-left: the same glowing red cap, and the steel housing frame is painted with amber and black diagonal hazard stripes. Bottom-right: the red cap dimmed to a dark unlit red, with a horizontal riveted steel latch bar locked across its middle. Absolutely no letters or words anywhere in the image.

**abort_lever_channel** (9:16, plate only)
> ASSET: abort lever channel. A tall vertical riveted steel slot plate filling the whole canvas: a rusty dark steel plate with rivets in the corners, and running down its centre a long narrow vertical channel (slot) that is PURE FLAT BLACK (#000000) inside, with a machined bevelled lip around the slot. Thin amber stencil tick marks beside the slot (no letters, no numbers). No handle in the slot, the slot is empty. The plate fills the canvas edge to edge.

**abort_lever_handle** (1:1, plate + abort_lever_channel)
> ASSET: abort lever handle, a single isolated object centred on a PURE FLAT BLACK (#000000) background. A chunky arcade pull handle seen straight on: a short dark steel shaft with a worn red (#EB4738) painted grip cap on top, rounded, with a small riveted steel collar at the base. The object fills about 70 percent of the frame, fully inside the frame with black margin on all sides, no shadow on the background, no ground plane, no text.

**bay_shutter** (16:9, plate + module_bay_frame.png, then plate + first
attempt) — third attempt accepted. Attempt 1 stamped "00-A" and two LEDs on
the lock plate; attempt 2 (told to match the bay frame's proportions)
reproduced the whole cabinet plate instead. The accepted prompt referenced
attempt 1 as the look-lock:
> ASSET: locked module bay shutter, a single isolated object. Reproduce the second reference image (the closed roller shutter inside a riveted steel frame) as ONE rectangular plate filling the whole canvas edge to edge, with the SAME framing and slats, but the small octagonal lock plate in the centre is completely plain: a single keyhole slot only, with NO stamped characters, NO numbers, NO letters, NO LEDs, NO coloured lights. Do not draw any other machine parts, no screens, no buttons, no cabinet around it. Fully opaque, rusty, scorched, dark, no pure black areas.

**maintenance_wall** (16:9, plate only)
> ASSET: maintenance workshop wall. A dim, moody industrial workshop interior seen straight on: a dark stained concrete-and-steel-panel back wall in the upper two thirds and a dark concrete floor with a subtle horizon line in the lower third. Along the far left and right edges only: a tool pegboard, hanging cable looms, a pipe run, a small shelf, all very dark. The entire centre of the frame is EMPTY (plain dark wall and floor) where a machine will later be placed. NO machine, NO arcade cabinet, NO screens, NO people, NO text or signage. Very dark and desaturated with faint warm amber ambient light from above, near-black shadows.

**System tier rows** (16:9, plate only). Shared framing sentence:
> ASSET: <SYSTEM> system tier row. On a PURE FLAT BLACK (#000000) background, exactly four identical SQUARE riveted dark steel mount plates in a single horizontal row, evenly spaced, same size, vertically centred, with clear black gaps between them and black margin above and below. Each plate carries one assembly, increasing in complexity left to right. [...] No text, no numbers, no labels anywhere.

Tier subjects:
- **compute**: Plate 1: a bare exposed green circuit board with a single small chip. Plate 2: a caged GPU stack behind a steel mesh cage with four visible cooling fans. Plate 3: a dense accelerator stack of stacked black boards with three horizontal glowing amber (#EDAD3D) rails. Plate 4: a sealed hexagonal armoured steel core with a red (#EB4738) glowing heart visible through a slit.
- **cooling**: Plate 1: a small old metal desk fan. Plate 2: a car radiator with two fans mounted on it. Plate 3: a liquid-cooling manifold with cyan (#79B8B6) coolant tubes and a small pump block. Plate 4: a phase-change cooler with frosted, ice-crusted pipes and a chilled steel chamber.
- **power**: Plate 1: a household mains plug lead coiled next to a small plastic power strip. Plate 2: a grey steel transformer box with a stencilled amber lightning-bolt symbol (a symbol only, no letters). Plate 3: four thick copper busbars mounted on ceramic insulators. Plate 4: an unstable red (#EB4738) glowing power core inside a cracked steel housing, red light leaking through the cracks.
- **backplane**: Each plate carries one horizontal steel backplane rail with a row of empty dark rectangular cartridge bay slots (dark charcoal slots, not pure black). Plate 1: a short rail with exactly 3 empty bays. Plate 2: exactly 5. Plate 3: exactly 7. Plate 4: a wide rail with exactly 10 empty bays in two rows of five. No cartridges in the bays.
- **control**: Each plate carries large chunky industrial rotary selector dials (knurled black bakelite knobs with an amber pointer line and a ring of plain amber tick marks, no numerals). Plate 1: exactly one large dial centred. Plate 2: two side by side. Plate 3: three in a row. Plate 4: four in a 2x2 arrangement.

Two tiers were regenerated individually (1:1, plate + that system's accepted
row as the second reference) and dropped into `_raw/sys_<system>_t4.png`,
which `build` picks up as overrides:
- **compute_t4** — the row drew a literal heart icon for the "glowing heart".
  > ASSET: COMPUTE system tier 4 tile, a single object. One SQUARE riveted dark steel mount plate centred on a PURE FLAT BLACK (#000000) background, filling about 80 percent of the frame with black margin all round, in exactly the same style, size and finish as the plates in the second reference image (the compute tier row). On the plate: a sealed hexagonal armoured steel core with heavy bolted plates, and through a narrow horizontal slit in its centre a round red (#EB4738) glowing reactor orb is visible, with red light bleeding onto the steel. The glow is a plain round orb, NOT a heart shape, NOT a symbol. No text, no numbers, no labels.
- **backplane_t4** — the row added a red button under the ten bays (red is
  reserved for the commit element).
  > ASSET: BACKPLANE system tier 4 tile, a single object. One SQUARE riveted dark steel mount plate centred on a PURE FLAT BLACK (#000000) background, filling about 80 percent of the frame with black margin all round, in exactly the same style, size and finish as the plates in the second reference image (the backplane tier row). On the plate: one wide steel backplane rail holding exactly 10 empty dark charcoal cartridge bay slots arranged in two rows of five, with a thin steel divider between the rows. Nothing else on the plate: NO red button, NO lights, NO LEDs, NO cartridges, no text, no numbers, no labels.

## Post-processing

Everything is one command, run from the repo root:

```powershell
python tools\asset_generator\cabinet_v2_post.py build
```

`build` is the recorded pipeline; the individual subcommands it composes are
available for one-offs:

```powershell
# cover-crop onto an exact canvas
python tools\asset_generator\cabinet_v2_post.py fit _raw\crt_bezel.png crt_bezel.png --size 1536x864
# knock an opening out (seed inside the opening) or a background (seed from the edges)
python tools\asset_generator\cabinet_v2_post.py knockout crt_bezel.png crt_bezel.png --rect 760,424,16,16
python tools\asset_generator\cabinet_v2_post.py knockout in.png out.png --auto-black
# split a sheet: commit states (2x2) and system rows (4x1)
python tools\asset_generator\cabinet_v2_post.py slice-grid _raw\commit_button_states.png . --cols 2 --rows 2 --names commit_idle,commit_armed,commit_danger,commit_busy --trim --pad-to 960x400 --knockout
python tools\asset_generator\cabinet_v2_post.py slice-grid _raw\sys_compute_row.png systems --cols 4 --rows 1 --names compute_t1,compute_t2,compute_t3,compute_t4 --trim-common --pad-to 480x480 --knockout
# review sheet of every final asset (written to _raw/contact_sheet.png)
python tools\asset_generator\cabinet_v2_post.py contact-sheet
```

What the pipeline does per asset:
- Backdrops and opaque plates: `fit` (Lanczos cover-crop) to the final canvas.
  The 1280x720 generator frames are upscaled 1.2-1.5x; they are decorative and
  read fine at that scale.
- Frames with openings: `fit`, then a flood-fill knockout seeded from the
  canvas centre over pixels with max(R,G,B) <= 10, with a 24-level feather so
  the inner lip does not alias. Seeding from the centre (not the edges) keeps
  black scorching on the frame itself opaque.
- Commit sheet: 2x2 cells, background knocked out from the cell edges, each
  cell trimmed to its housing and fitted onto 960x400.
- Lever: channel `fit` to 585x1040 with the slot knocked out from a centre
  seed; handle background knocked out, trimmed and fitted onto 320x320.
- System rows: 4x1 cells, background knocked out, every cell cut to the first
  plate's size centred on its own plate (`--trim-common`; thin frost/glow spill
  past the plate is ignored by a 6 px morphological opening), fitted onto
  480x480. `_raw/sys_<system>_t<n>.png`, if present, replaces that tier.

`tools/extract_generated_alpha.gd` was not needed: no generation came back
with a light transparency grid (all backgrounds were requested as pure black).

## Regenerating an asset

1. Generate with the preamble above plus the asset's prompt, passing the plate
   and (for frames / tiles) the accepted family anchor in `reference_image_paths`.
2. Check the result for baked text, extra red elements, emblems, or an opening
   that is not flat black. Reject and re-prompt rather than retouching.
3. Copy the accepted file over the matching name in `_raw/` (rows are
   `sys_<system>_row.png`; single-tier overrides are `sys_<system>_t<n>.png`).
4. Run `python tools\asset_generator\cabinet_v2_post.py build` and review
   `_raw/contact_sheet.png`.
5. Launch Godot once (or `godot --headless --path . --quit`) so it writes the
   `.import` files; never hand-write those.
6. If a frame's thickness changed, update its `margins` in
   `presentation/asset_catalog.json` (`cabinet_v2.frames`).
