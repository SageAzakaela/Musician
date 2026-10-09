"""Build Musician using local compile-only game and ZombieBuddy libraries."""
from pathlib import Path
import argparse, hashlib, os, shutil, subprocess, tempfile, zipfile

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--game', required=True, type=Path)
parser.add_argument('--ecj', type=Path, help='Eclipse compiler JAR; omit to use javac from PATH')
parser.add_argument('--test', action='store_true')
parser.add_argument('--sampler-test', action='store_true', help='Offline sampler, composition, master-level and Lua bridge tests; no audio or MIDI devices')
# Native input/output probes belong to the archived pre-0.12.0 engine.
parser.add_argument('--input-test', action='store_true', help='Hardware-free MIDI routing and Lua bridge checks; no MIDI scan, input or audio output')

parser.add_argument('--audio-probe',action='store_true',help='Run opt-in silent streaming tests on the default output and IXO22 if present')
parser.add_argument('--diagnose', action='store_true', help='List MIDI inputs; does not open devices or play audio')
parser.add_argument('--demo',type=Path,help='Render an offline WAV demonstration; does not play audio')
args=parser.parse_args()
java=args.game/'jre64/bin'/('java.exe' if os.name=='nt' else 'java')
deps=[args.game/'projectzomboid.jar',args.game/'ZombieBuddy.jar']
for dep in [java,*deps]:
    if not dep.is_file(): parser.error(f'Missing {dep}')
cp=os.pathsep.join(str(p.resolve()) for p in deps)
compiler=([str(java),'-jar',str(args.ecj),'-22','-proc:none','-warn:none'] if args.ecj else ['javac','--release','22','-proc:none'])
with tempfile.TemporaryDirectory(prefix='dead-air-') as temporary:
    classes=Path(temporary)/'classes';classes.mkdir()
    subprocess.run([*compiler,'-cp',cp,'-d',str(classes),*map(str,sorted((ROOT/'src').rglob('*.java'))),*map(str,sorted((ROOT/'vendor/gervill/src').rglob('*.java')))],check=True)
    jar=ROOT/'Contents/mods/DeadAir/42/media/java/client/DeadAir.jar'
    jar.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(jar,'w',zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\nImplementation-Title: Musician\nImplementation-Version: 0.13.2\n\n')
        for file in sorted(classes.rglob('*.class')): archive.write(file,file.relative_to(classes).as_posix())
    if args.input_test or args.sampler_test or args.test or args.diagnose or args.demo or args.audio_probe:
        testcp=cp+os.pathsep+str(classes)+os.pathsep+str(ROOT)
        subprocess.run([*compiler,'-cp',testcp,'-d',str(classes),*map(str,sorted(p for p in (ROOT/'tests').glob('*.java') if p.name not in ('WindowsMidiInputTest.java','DirectAudioSmoke.java')))],check=True)
        if args.input_test or args.test:
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.MidiInputTest'],check=True)
        if args.input_test:
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.BridgeTest'],check=True,cwd=args.game)
        if args.input_test or args.test or args.sampler_test:
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.OptionsTextTest',str(ROOT/'Contents/mods/DeadAir/42/media/lua/client/DeadAir.lua')],check=True,cwd=args.game)
        if args.test or args.sampler_test:
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.AudioResponseTest',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.HotfixAudioTest',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.SoundfontTest',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.JavaSamplerTest',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.EngineTest',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.GuitarInputTest',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.LiveMidiTest',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.CompositionTest',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.VolumeTest',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.BridgeTest'],check=True,cwd=args.game)
        if args.test:
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.AnimationTest',str(ROOT/'Contents/mods/DeadAir')],check=True,cwd=args.game)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.FbxImportTest',str(ROOT/'Contents/mods/DeadAir')],check=True,cwd=args.game)
            subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.SongDataTest',str(ROOT/'Contents/mods/DeadAir')],check=True,cwd=args.game)
        if args.test: subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.MidiImportTest'],check=True)
        if args.audio_probe: subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.AudioOutputSmoke',str(ROOT/'Contents/mods/DeadAir/common')],check=True)
        if args.diagnose: subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.Diagnostics'],check=True)
        if args.demo: subprocess.run([str(java),'-cp',testcp,'azakaela.deadair.RenderDemo',str(ROOT/'Contents/mods/DeadAir/common'),str(args.demo.resolve())],check=True)
common=ROOT/'Contents/mods/DeadAir/common'
shutil.copytree(ROOT/'vendor/gervill',common/'library-sources/gervill',dirs_exist_ok=True)
(common/'licenses').mkdir(parents=True,exist_ok=True)
shutil.copy2(ROOT/'vendor/gervill/LICENSE.txt',common/'licenses/Gervill-LICENSE.txt')
shutil.copy2(ROOT/'THIRD_PARTY.md',common/'licenses/Musician-THIRD-PARTY.md')
shutil.copy2(ROOT/'LICENSE',common/'licenses/Musician-LICENSE.txt')
print('Built',jar)
print('SHA-256',hashlib.sha256(jar.read_bytes()).hexdigest())
