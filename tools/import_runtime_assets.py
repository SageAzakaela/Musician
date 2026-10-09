"""Copy verified, separately licensed runtime assets from a local Musician mod."""
from pathlib import Path
import argparse, hashlib, json, shutil

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mod',required=True,type=Path,help='Existing Musician mod root containing 42/ and common/')
    args=parser.parse_args()
    source=args.mod.expanduser().resolve(strict=True)
    target=(ROOT/'Contents/mods/DeadAir').resolve()
    if source==target:parser.error('Choose an existing installation, not this repository output.')
    entries=json.loads(Path(__file__).with_name('runtime-assets.json').read_text(encoding='utf-8'))['files']
    copies=[]
    for item in entries:
        relative=Path(item['path']);src=(source/relative).resolve();dest=(target/relative).resolve()
        if not src.is_relative_to(source) or not dest.is_relative_to(target):parser.error('Asset path leaves its mod directory.')
        if not src.is_file():parser.error(f'Missing runtime asset: {relative}')
        if hashlib.sha256(src.read_bytes()).hexdigest()!=item['sha256']:parser.error(f'Asset differs from 0.13.2: {relative}')
        if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest()!=item['sha256']:
            parser.error(f'Existing destination differs; preserve your edit before importing: {relative}')
        copies.append((src,dest))
    for src,dest in copies:
        dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
    print(f'Imported {len(copies)} verified runtime assets into the local build directory. Source installation unchanged.')
    print('Assets retain their original terms and are ignored by Git; see THIRD_PARTY.md.')

if __name__=='__main__':main()
