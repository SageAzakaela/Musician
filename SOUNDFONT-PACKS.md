# Soundfont packs for Musician

Musician 0.13.0 accepts personal SF2 files and soundfonts supplied by other enabled mods.
Packs contain data and one Lua registration file. They need no Java component of their
own and no extra audio installer. Musician still needs the installed ZombieBuddy loader.

## For players

Open Options > Mods > Musician > Soundfonts / instrument sounds, or the songbook's
Sounds button. Select an instrument on the left, choose a bank on the right, search
its presets, and click Preview. Assign sound changes the draft; Apply sounds saves it.
You can mix presets from several banks. Use included sound resets the selected instrument;
Reset all resets every assignment. Close discards unapplied mapping edits.

For personal files, use Browse, or paste a quoted or unquoted full .sf2 path and Add file.
Files stay where you put them. For Workshop packs, subscribe, enable the pack alongside
Musician, and restart the game. Registered packs appear in the bank menu. Installing a
pack does not silently replace your current sounds; choose its presets yourself.

Stop recording/song playback before Apply. Applying replaces the loaded timbres and ends
held live notes, while preserving your MIDI connection and audio output. Previews are
private and never produce performance animations or zombie noise. The saved choices apply
to your live instrument, written songs, editor playback and nearby musicians you hear.

These are local listening choices: the server receives no file paths or soundfont files.
Other players hear their own chosen banks. A missing/disabled pack or missing preset
falls back to the included instrument while retaining the saved assignment. Enable the
pack again and reconnect audio or press Apply to restore it.

Settings: Zomboid/Lua/MusicianSoundfonts.properties, with a .bak of the previous save.
Supported: uncompressed SF2; up to 32 personal files and 32 registered packs, 4096 presets
per bank, 256 MiB per file and 512 MiB combined across selected bank files. Banks parse on
a background worker when inspected or used, not when their Lua registration runs.
SF3, SFZ, VST plugins and audio-effect plugins are not supported.

The UI shows zero-based bank/program numbers. Piano and keytar share the same profile.
Full kit, kick, floor tom and snare have separate sound assignments. Drum note numbers
remain GM percussion keys; assigning a kit does not translate proprietary drum layouts.

## For pack authors

Use a unique mod ID and a stable key for each bank. Example folder structure:

    YourSoundfontPack/
      42/mod.info
      42/media/lua/client/YourSoundfontPack_Register.lua
      common/media/soundfonts/YourBank.sf2
      common/licenses/YourBank-LICENSE.txt

42/mod.info:

    name=Your Soundfont Pack
    id=YourSoundfontPack
    author=Your name
    description=Optional SF2 presets for Musician. Choose them from its Sounds window.
    require=\DeadAir
    versionMin=42.21
    versionMax=42.21

The internal dependency ID remains DeadAir even though the mod is named Musician.
The registration file contains:

```lua
require "MusicianSoundfonts"
MusicianSoundfonts.registerPack {
    modId = "YourSoundfontPack",
    key = "main",
    name = "Your Soundfont Pack",
    path = "media/soundfonts/YourBank.sf2",
}
```

The path is relative to this mod's common folder. Absolute paths, paths leaving that
folder and links outside it are rejected. The registration ID is modId + key, so keep
both stable across updates. Names can change without breaking assignments. Register
additional files using additional keys. Only enabled mods are resolved.

Do not put a Java JAR or native library in a soundfont pack. Add Musician as a required
Workshop item when publishing. Include the bank's license/credits and use soundfonts
you have permission to redistribute. Personal-file loading does not upload a user's bank.

The accompanying template omits an SF2: add your own redistributable bank and its license
before testing or publishing it. The main Musician release includes only GeneralUser GS.
