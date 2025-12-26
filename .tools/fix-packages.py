#!/usr/bin/env python3
"""
Fix misplaced package names in Dockerfiles
"""
import re
import sys
from pathlib import Path

def fix_dockerfile(filepath):
    """Fix a single Dockerfile"""
    content = filepath.read_text()
    original = content
    
    # Pattern: cleanup line followed by package names on next lines
    pattern = r'(&& rm -rf /var/lib/apt/lists/\* /tmp/\* /var/tmp/\*)\n((?:\s+\S+.*\n?)+?)(\n##|\nFROM|\nRUN|\nUSER|\nENV|\nCOPY|\nCMD|\nEXPOSE|\nWORKDIR|$)'
    
    match = re.search(pattern, content)
    if not match:
        return False, "No pattern found"
    
    cleanup_line = match.group(1)
    misplaced_text = match.group(2)
    next_section = match.group(3)
    
    # Extract actual package names (lines starting with whitespace + alphanumeric)
    package_lines = []
    for line in misplaced_text.strip().split('\n'):
        stripped = line.strip()
        # Only consider lines that look like package names (alphanumeric, hyphens, colons)
        if stripped and re.match(r'^[a-z0-9][a-z0-9\-:.+]*\\?$', stripped, re.IGNORECASE):
            pkg = stripped.rstrip('\\').strip()
            if pkg and not pkg.startswith('#'):
                package_lines.append(f"\t\t\t\t{pkg} \\")
    
    if not package_lines:
        return False, "No packages found"
    
    # Find the install line
    install_pattern = r'(apt-get install -y --no-install-recommends)\s+\\\n\s*\\\n'
    install_match = re.search(install_pattern, content)
    
    if not install_match:
        return False, "Install line not found"
    
    # Build the fix
    packages_block = '\n'.join(package_lines)
    new_install = f"{install_match.group(1)} \\\n{packages_block}\n"
    
    # Replace empty install with packages
    content = re.sub(install_pattern, new_install, content)
    
    # Remove the misplaced section
    content = content.replace(cleanup_line + '\n' + misplaced_text, cleanup_line)
    
    if content != original:
        filepath.write_text(content)
        return True, f"Fixed - added {len(package_lines)} packages"
    
    return False, "No changes needed"

def main():
    root = Path('.')
    dockerfiles = list(root.rglob('Dockerfile'))
    dockerfiles = [f for f in dockerfiles if '.git' not in str(f)]
    
    print(f"🔍 Found {len(dockerfiles)} Dockerfiles")
    
    fixed = 0
    errors = 0
    
    for dockerfile in dockerfiles:
        try:
            changed, msg = fix_dockerfile(dockerfile)
            if changed:
                print(f"✅ {dockerfile}: {msg}")
                fixed += 1
        except Exception as e:
            print(f"❌ {dockerfile}: {e}")
            errors += 1
    
    print(f"\n📊 Summary: {fixed} fixed, {errors} errors, {len(dockerfiles)-fixed-errors} skipped")

if __name__ == '__main__':
    main()
