# Building and testing Musician

The repository starts from the 0.13.2 implementation. A clone can compile the Java
code, but runtime sound/animation assets are supplied by an existing local Musician
installation. The import step only reads that installation; it never changes it.

## Prerequisites

- Python 3.10 or newer.
- A Java 22+ JDK with `javac` on PATH, or an ECJ JAR that supports `-22`.
- Project Zomboid 42.21 and ZombieBuddy 2.3+ installed locally. The build uses
  `projectzomboid.jar`, `ZombieBuddy.jar`, and the game's `jre64/bin/java.exe`.
- For Lua tests: `python -m pip install lupa` in your development environment.

No credentials, game JARs or proprietary SDK files belong in the repository.

## Import the runtime assets

Install Musician from Workshop, then point the importer at its **mod root** containing
`42/` and `common/`. A typical Windows location is:

```powershell
python tools/import_runtime_assets.py --mod "C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\3816180767\mods\DeadAir"
```

A local copy such as `%USERPROFILE%\Zomboid\mods\DeadAir` also works. The script checks
the complete asset list against the 0.13.2 manifest before copying anything. If your
installed version has different assets, it reports the mismatch instead of silently
mixing releases. It copies only the listed sound bank, animation/prop assets, poster,
and bank notices. It does not import a JAR, Lua code, saves, personal fonts or settings.

Imported assets are ignored by Git and retain their existing licenses. Do not force-add
them. The importer is a local development convenience, not a new redistribution grant.

## Compile

```powershell
python build.py --game "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid"
```

To use ECJ instead of a JDK compiler, append `--ecj "C:\Tools\ecj.jar"`.
Classes target Java 22. The built JAR is:

`Contents/mods/DeadAir/42/media/java/client/DeadAir.jar`

The build stages the sampler source and license notices into the mod's `common/`
directory, which is also ignored by Git. Keep those notices with any distributed JAR.

## Run regression checks

```powershell
python tools/check_vendor.py
python build.py --game "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid" --input-test --sampler-test
python tests/lua_test.py --game "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid"
```

`--input-test` checks MIDI parsing, routing and the real game Lua-to-Java bridge.
`--sampler-test` renders sound to memory and checks instrument/sample selection,
velocity curves, chords, controllers, playback, recording, soundfont mapping, remote
MIDI and bounded output queues with a simulated audio line. Neither flag opens hardware.

The Lua suite uses the installed game's Lua sources with UI/network stand-ins. It
covers song editing, arrangements, clips, paper data, scale controls, input monitoring,
instrument actions and multiplayer routing. If Lupa is in a separate location, pass
`--lupa-path "C:\Tools\python-deps"`.

The broader `--test` option also exercises game animation parsers and the native FBX
importer. It requires the imported animation assets and the game's native libraries.
`--audio-probe` explicitly opens audio devices; `--diagnose` enumerates MIDI devices.
Neither is part of the default or offline workflow.

Automated checks do not establish controller-to-headphone latency, visual animation
quality or compatibility with every server. Those require actual playtesting.

## Local installation

Fully exit Zomboid first. Back up your existing mod, then copy the assembled
`Contents/mods/DeadAir` directory to your local `Zomboid/mods/DeadAir` directory.
Avoid enabling two copies with the same `DeadAir` mod ID. Restart the game, enable
Musician and approve the changed Java JAR. Test on a spare save before publishing.

Build and import commands never modify a game installation, Workshop subscription,
save, audio driver or MIDI-device configuration.
