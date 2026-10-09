"""Run the same Lua/editor fixtures in PZ Kahlua, without booting the game or audio."""
from pathlib import Path
import argparse,contextlib,inspect,io,os,runpy,subprocess,sys,tempfile,types
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--game',required=True,type=Path);p.add_argument('--ecj',type=Path)
a=p.parse_args();root=Path(__file__).resolve().parents[1];game=a.game.resolve()
java=game/'jre64/bin'/('java.exe' if os.name=='nt' else 'java')
compiler=([str(java),'-jar',str(a.ecj.resolve()),'-22','-proc:none','-warn:none'] if a.ecj else ['javac','--release','22'])
with tempfile.TemporaryDirectory(prefix='musician-kahlua-') as temporary:
    folder=Path(temporary);manifest=[];serial=0
    class Recorder:
        def __init__(self,**kwargs):manifest.append('reset')
        def execute(self,script,*args):
            global serial
            serial+=1;mode='run'
            if args:
                assert script=='assert(loadstring(...))';script=args[0];mode='compile'
            caller=inspect.stack()[1];label=Path(caller.filename).name+':'+str(caller.lineno)
            name=f'{serial:04}.lua';(folder/name).write_text(script,encoding='utf-8')
            manifest.append('\t'.join((mode,name,label)))
    package=types.ModuleType('lupa');module=types.ModuleType('lupa.lua51');module.LuaRuntime=Recorder
    sys.modules['lupa']=package;sys.modules['lupa.lua51']=module
    sys.argv=['lua_test.py','--game',str(game)]
    # Capture fixtures only; their Python PASS banners are not test results yet.
    with contextlib.redirect_stdout(io.StringIO()):
        runpy.run_path(str(root/'tests/lua_test.py'),run_name='__main__')
    (folder/'manifest.tsv').write_text('\n'.join(manifest)+'\n',encoding='utf-8')
    cp=str(game/'projectzomboid.jar')
    subprocess.run([*compiler,'-cp',cp,'-d',str(folder),str(root/'tests/GameLuaTest.java')],check=True)
    subprocess.run([str(java),'-cp',str(folder)+os.pathsep+str(game/'*'),'azakaela.deadair.GameLuaTest',str(folder)],check=True,cwd=game)
