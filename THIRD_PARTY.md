# Third-party code and runtime assets

The root MIT license covers Musician's original implementation. It does not replace
the terms of the components listed here or grant rights to assets imported locally.

## Gervill — included source

- Original author: Karl Helgason / Sun Microsystems; original per-file notices remain.
- Upstream fork: https://github.com/bluenote10/gervill
- Pinned commit: `24e35d957b0299122a9e1921da2a31ab2b5d4cb1`
- License: GPL version 2 with the Classpath exception, as stated in each source file.
- Full terms: [vendor/gervill/LICENSE.txt](vendor/gervill/LICENSE.txt).
- Modifications and source hashes: [vendor/gervill/provenance.json](vendor/gervill/provenance.json).

The exception is retained on the modified library. The sampler is compiled into the
mod JAR; the build also places its matching source and notices in the generated mod's
`common/library-sources/gervill` and `common/licenses` directories. Retain these when
distributing builds. The independent Musician code remains under its own license.

The current build includes no native FluidSynth, PortAudio or ASIO helper binaries.

## GeneralUser GS — imported locally, not committed

- Author: S. Christian Collins.
- Website: https://www.schristiancollins.com/generaluser
- Runtime bank: GeneralUser GS 2.0.3.
- Source: https://github.com/mrbumpy409/GeneralUser-GS/tree/684543d5e5efaef08d02be50dcda8d552478fa60

The Workshop runtime uses the unchanged bank under its own License v2.0. That license
describes uncertainty about some legacy sample origins; the bank is not represented
as CC0 or as Musician-authored recordings. The asset importer copies the existing
bank's license and README alongside it. Consult those terms for redistribution.

## Animations and instrument artwork — imported locally, not committed

The Workshop runtime credits:

- [Aza's Playable Guitar](https://steamcommunity.com/sharedfiles/filedetails/?id=2731005255)
- [Playable Guitar B42 port](https://steamcommunity.com/sharedfiles/filedetails/?id=3531326965)
- [Lifestyle](https://steamcommunity.com/sharedfiles/filedetails/?id=2997342681)
- [Simple Playable Pianos by PseudonymousEd](https://steamcommunity.com/sharedfiles/filedetails/?id=2465017864)

Imported FBX/X clips, adapted animation XML definitions, the violin-bow artwork, and
derived rig assets are outside the MIT grant. They are excluded from Git tracking.
The original Blender authoring script is included, but it expects an existing rig
from the runtime package; its output does not become wholly original artwork merely
because the script is open source. Source access is not permission to relicense or
redistribute another creator's assets.

## Game and loader — external dependencies

Project Zomboid is by The Indie Stone. The game JAR, models, textures and other game
files are not included here. The build reads a user's local installation.

ZombieBuddy: https://github.com/zed-0xff/ZombieBuddy. Its JAR is a local build dependency,
not included in this repository. Follow its upstream license and installation guide.

## MIDI content

The parser and procedural musical patterns are original Musician code. No Groove
Monkee, Unison, personal MIDI folders, commercial clips or private configuration are
included. Compatibility names do not imply bundled content or endorsement.

## Project image

`docs/preview.png` is Musician's Workshop illustration, based on a Project Zomboid
gameplay screenshot with a title treatment. It is not part of the source-code license;
the underlying game imagery remains subject to its respective rights.
