#!/usr/bin/env python3
import re
from pathlib import Path
import sys

def fix_dockerfile(filepath):
    """Fix package order in Dockerfile"""
    path = Path(filepath)
    content = path.read_text(encoding='utf-8')
    original = content

    # Match the problematic pattern
    # Group 1: install line
    # Group 2: optional first package(s)
    # Group 3: cleanup commands
    # Group 4: remaining packages after cleanup
    pattern = r'(apt-get install -y --no-install-recommends\s*\\\s*\n)((?:\s+[^\n]+\\\s*\n)?)((?:\s*&& apt-get clean[^\n]*\n[^\n]*var/lib[^\n]*\n))((?:[^\n]*[a-z0-9\-\.]+[^\n]*\n?)+)'

    match = re.search(pattern, content, re.M | re.S)
    if not match:
        return False, "No match found"

    install_line = match.group(1)
    first_pkgs = match.group(2)
    cleanup = match.group(3)
    rest_pkgs = match.group(4)

    # Collect all packages
    packages = []

    # From first_pkgs if exists
    if first_pkgs.strip():
        for line in first_pkgs.split('\n'):
            pkg = line.strip().replace('\\', '').strip()
            if pkg:
                packages.append(pkg)

    # From rest_pkgs
    for line in rest_pkgs.split('\n'):
        pkg = line.strip().replace('\\', '').strip()
        if pkg and not pkg.startswith('&&') and not pkg.startswith('#'):
            packages.append(pkg)

    if not packages:
        return False, "No packages found"

    # Rebuild with correct format
    new_pkg_block = ""
    for i, pkg in enumerate(packages):
        if i < len(packages) - 1:
            new_pkg_block += f"                {pkg} \\\n"
        else:
            new_pkg_block += f"                {pkg} \\\n"

    # Replace in content
    new_run = install_line + new_pkg_block + cleanup
    content = content[:match.start()] + new_run + content[match.end():]

    if content != original:
        path.write_text(content, encoding='utf-8', newline='\n')
        return True, f"Fixed - moved {len(packages)} packages"

    return False, "No changes needed"

if __name__ == '__main__':
    files = [
        'dev/bun/latest/Dockerfile',
        'dev/bun/canary/Dockerfile'
    ]

    for f in files:
        fixed, msg = fix_dockerfile(f)
        status = "✓" if fixed else "○"
        print(f"{status} {f}: {msg}")
