"""Check that vendored Gervill sources match their recorded provenance."""
from pathlib import Path
import hashlib,json

def main():
    root=Path(__file__).resolve().parents[1]/'vendor/gervill'
    recorded=json.loads((root/'provenance.json').read_text(encoding='utf-8'))['sourceSha256']
    actual={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/'src').rglob('*.java')}
    if actual!=recorded:
        changed=sorted(k for k in actual.keys()|recorded.keys() if actual.get(k)!=recorded.get(k))
        raise SystemExit('Vendor provenance mismatch: '+', '.join(changed))
    print(f'PASS: {len(actual)} vendored sampler sources match the change/hash manifest.')

if __name__=='__main__':main()
