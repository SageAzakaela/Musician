# Changelog

## 0.15.0

- Reclaimed space for the music: removed duplicate heading/part rows, grouped
  the common note tools, moved extra actions into More, and hid shortcut hints
  by default. The arrangement automatically fits its tracks until manually resized.
- Added View customization: Balanced, Notes focus and Arrangement focus presets;
  tracks/velocity/overview/hints toggles; compact or comfortable controls; three
  track heights; resizable inspector and velocity lane; Fit tracks and Reset view.
- Added Zomboid, Charcoal, Slate and High contrast themes, preset accent colors,
  and custom #RRGGBB accents for notes, clips, selections and loop/velocity markers.
  Note/clip label ink adapts for contrast. Very dark accents are lifted for visibility.
- The Edit inspector follows note, clip and track selection after gestures finish.
  Song details stay pinned when chosen; extra controls are folded into Advanced.
- Layout and colors save locally, including panel sizes and visibility. Existing
  version-1 layout preferences migrate; Reset view leaves music and audio alone.

Validation: full Lua 5.1 and installed-game Kahlua suites; actual installed Lua
widget callbacks with strict drawing-argument checks; multi-screen/font/theme
layouts, custom-color contrast, preference migration/reopen/reset, resize/cancel,
and unchanged song notes/history. Production Lua render previews reviewed.
UI/audio/network remain simulated in tests; in-game playtest still required.
Lua-only update; the Java engine remains 0.13.2.

## 0.14.2

- The arrangement now resizes smoothly in pixels, even with just one or two tracks.
  Grab the wider **Drag to resize tracks** bar between the tracks and piano roll.
  It highlights on hover, remembers the size, and supports Escape to cancel.
- Resizing keeps the piano roll centered on the same pitches and reserves room
  for notes. Smaller windows temporarily clamp the arrangement without losing
  the preferred size. Expanding it reveals more tracks and adjusts track scrolling.
- Fixed the Details inspector repeatedly sending missing label coordinates to
  the game's drawing API, causing the `Number.doubleValue()` error popup.
- Kept the visible-track counter from overlapping its heading at larger fonts.

Validation: reproduced the label failure with strict drawing-argument checks;
the complete Lua/editor/widget/simulated-network suite passes in Lua 5.1 and the
installed game's Kahlua VM. Resize checks cover individual pixels, one/eight tracks,
limits, mouse release outside the window, cancellation, pitch focus, preferences
and window resizing. Native UI/audio remain simulated; in-game playtest pending.
Lua-only update; the Java engine remains 0.13.2.

## 0.14.1

- Fixed the 0.14.0 clip-selection crash that also prevented recording from starting.
  Zomboid's Kahlua VM has no global `next`; the previous Lua 5.1-only editor tests
  missed that incompatibility. Recording now prepares its undo state before audio
  starts, and the full editor regression suite also runs in the installed game VM.
- Recording follows the take past the original clip boundary. Stop combines the
  final take with the original notes exactly once, including held notes, and saves
  it into the existing clip when applicable. Empty takes do not add clips.
- Overdubbing a loop keeps its existing repetitions and makes the touched clip
  independent, so recorded notes cannot disappear when loop repeats rebuild.
  Unrelated clips retain their notes and lengths. Undo restores the original loop.
- Empty piano rolls start around middle C. Follow centers the recording's actual
  pitch range, including a held first note; turn Follow off for manual navigation.
  Recording temporarily shows all pitches so scale/fold filters cannot hide input.
  Filters return after Stop. Undo restores the previous vertical zoom as well.

Validation: reproduced the crash in the actual game Kahlua VM before the fix; full
editor/widget/simulated-network suite passes there afterward. Added recording,
loop overdub, note retention, empty/full clip list, view-follow and save/reopen
checks. UI/audio hardware remain simulated; in-game listening still needs a check.
Lua-only hotfix; the Java engine remains 0.13.2.

## 0.14.0

- Added a draggable piano-roll loop brace, 1/2/4/8-bar presets, and Loop selection
  (Ctrl+L). A loop may start after an intro that plays once. Exact clip/loop start
  and length fields live in the Inspector; shortening protects source notes.
- Clip and note snapping are independent. Each has fixed/adaptive modes and an off
  setting. Adaptive shows its actual interval; Alt bypasses clip/brace snapping.
- Ctrl/Shift-click selects several clips on a track. Move, duplicate and delete
  operate on that group and preserve gaps. Ctrl+E splits at the cursor; Ctrl+J
  consolidates selected clips. Right-click a repetition to make it an independent
  variation. All song edits support undo/redo, including split held notes.
- Moved clip settings into a collapsible inspector. Added a resizable tracks/notes
  divider, dimmed repetition context, Fit clip, and scrollable shortcut help.
  The inspector scrolls on small screens. Window/divider/snap preferences are saved
  locally when closing the editor and never sent with songs.
- Existing songs remain readable. Update multiplayer clients and server together
  for the new loop-start metadata. Editing during playback remains unsupported.
- Lua-only update; the distributed 0.13.2 Java engine and audio assets are unchanged.

Validation: full Lua/editor/simulated-network suite, production clip operations,
loop/selection mouse and keyboard paths, atomic capacity/overlap rejection, undo,
save/reopen/playback, installed-game widget callbacks with Java UI stand-ins, and
rendered layouts at three sizes. Actual in-game visuals/listening remain pending.

## 0.13.3

- Clip moves and edge drags snap the destination to the grid. An off-grid clip no
  longer keeps its old offset through every drag. Trimming against a note tail
  rounds the protected edge up to the grid without changing the played notes.
- Added Timing controls for exact start bar, total clip length and loop source
  length. Fractional bars are supported; one quarter of a bar is one beat.
- Changing a loop's period rebuilds repeats from the original source. Old generated
  repeats cannot leak into a longer source. Edits reject overlaps, lost source notes
  and note-capacity overflow before applying, and participate in undo/redo.
- Loop length labels show the stored value instead of rounding to two significant
  digits. Existing songs keep their timing until edited.
- Lua-only update; the distributed 0.13.2 Java engine and audio assets are unchanged.

Validation: full Lua/editor/simulated-network suite, exact six-cycle repair,
fractional/triplet periods, save/reopen/playback, and installed-game widget callbacks
with Java UI stand-ins. In-game visual and listening checks remain pending.

## 0.13.2

- Fixed SF2 modulator curve decoding that made quiet piano notes barely audible and
  caused a sudden volume jump around half velocity.
- Added Natural and Soft touch listening responses. Soft touch helps gentle playing;
  recordings, diagnostic counters and multiplayer MIDI keep the original velocities.
- Reduced Fast output to a 128-frame queue target, with 64-frame writes. Audio waits
  for space before rendering, including when a driver allocates a larger buffer.
- Added regression coverage for quiet notes, smooth dynamics, curve types and output
  queue behavior. Physical latency and crackling still require a device playtest.

## 0.13.1

- Fixed incorrect sample selection after empty soundfont key/velocity intersections,
  affecting piano, acoustic guitar, bass, banjo, violin and drums.
- Removed an obsolete native MIDI queue safeguard that could disable Java playback
  after dense controller and note traffic.
- Added full note/velocity sample-selection and fast-input regression checks.

## 0.13.0

- Added personal SF2 files, per-instrument preset mapping and soundfont-pack mods.
- Added private sound previews, saved local assignments and fallback to included sounds.

## 0.12.0

- Moved the Workshop audio package to the bundled Java Gervill sampler and Java Sound
  output. Native FluidSynth/ASIO helper binaries are not part of this build.

## Source publication

The public repository starts with the 0.13.2 code. Earlier private development history,
local backups, personal MIDI packs and imported runtime assets are not included.
