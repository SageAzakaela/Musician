# Contributing

Thanks for taking a look. Small, focused fixes are easiest to review. For a larger
feature, open an issue describing the player-facing behavior before building it.

## Where things live

- `src/azakaela/deadair/`: MIDI input, soundfont synthesis, audio output, recording,
  playback, clip importing, live MIDI transport and the Java animation bridge.
- `Contents/mods/DeadAir/42/media/lua/client/`: editor, piano roll, arrangement,
  library, soundfont setup, performance actions and options.
- `Contents/mods/DeadAir/42/media/lua/shared/`: song data, validation, paper items,
  instrument-kit data and live protocol.
- `Contents/mods/DeadAir/42/media/lua/server/`: authoritative multiplayer handling.
- `vendor/gervill/`: modified sampler source, under its existing license.
- `tests/`: offline Java/audio and Lua/UI/network checks.
- `authoring/`: optional Blender animation authoring; requires imported runtime rigs.
- `examples/soundfont-pack/`: a pack template with no bank bundled.

## Before sending a pull request

Follow [the build guide](docs/BUILDING.md), run the checks relevant to your change,
and explain what changed and how you tested it. Be explicit about anything you could
not verify in-game. Include reproduction steps for a bug fix when possible.

Keep saved songs and the internal `DeadAir` identifiers compatible. Editor audition
and recording-monitor audio must stay private: no network broadcast or zombie noise.
Incoming MIDI velocities should remain intact in recordings and network messages.
Do not make optional device probes run during imports, builds or ordinary tests.

Please leave unrelated refactors out of fixes. Do not commit game binaries, native
audio runtimes, personal settings, commercial MIDI packs, imported assets or logs
containing private data. `.gitignore` is a convenience, not an asset license.

If you change Gervill, retain its copyright/license notices, describe the change in
`vendor/gervill/provenance.json`, and update the affected source hashes. Changes to
Musician's original code use the repository's MIT license; vendor changes retain the
vendor's license. No blanket relicensing of third-party material is intended.
