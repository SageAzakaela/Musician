# Changelog

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
