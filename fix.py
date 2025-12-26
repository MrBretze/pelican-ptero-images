#!/usr/bin/env python3
import re
from pathlib import Path

def fix_dockerfile(filepath):
    content = filepath.read_text()
    original = content
    
    # Pattern: install with empty line, cleanup, then packages
    pattern = r'(apt-get install -y --no-install-recommends)\s*\\\n\s*\\\n\s*(&& apt-get clean[^\n]*\n[^\n]*?/var/lib/apt[^\n]*\n)((?:\s+[a-z0-9][^\n]*\n)+)'
    
    match = re.search(pattern, content)
    if not match:
        return False, "No match"
    
    install = match.group(1)
    cleanup = match.group(2)
    packages = match.group(3)
    
    # Build fixed version
    fixed = f"{install} \\\n{packages}\t\t\t{cleanup}"
    content = content.replace(match.group(0), fixed)
    
    if content != original:
        filepath.write_text(content)
        return True, "Fixed"
    return False, "No change"

for df in Path('.').rglob('Dockerfile'):
    if '.git' not in str(df):
        try:
            changed, msg = fix_dockerfile(df)
            if changed:
                print(f"✅ {df}")
        except: pass
