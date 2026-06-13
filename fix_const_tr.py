#!/usr/bin/env python3
"""Fix 'const Widget(context.tr(...))' patterns across all screen files.
context.tr() is a runtime call and cannot be used inside const constructors."""

import os, re

D = os.path.dirname(__file__)
FRONTEND = os.path.join(D, 'frontend/lib')

# Files to scan
files = []
for root, dirs, fnames in os.walk(FRONTEND):
    for f in fnames:
        if f.endswith('.dart'):
            files.append(os.path.join(root, f))

# Patterns to fix - remove 'const ' before widgets that contain context.tr()
# Pattern: const Text(context.tr(...)) -> Text(context.tr(...))
# Pattern: const SnackBar(content: Text(context.tr(...))) -> SnackBar(content: Text(context.tr(...)))

# We need to be careful with multi-line patterns
# Strategy: process each file line by line, but track const blocks

fixed_count = 0
total_replacements = 0

for fpath in files:
    with open(fpath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    
    # Fix 1: const Text(context.tr(...)) -> Text(context.tr(...))
    # This handles single-line cases
    content = re.sub(
        r'\bconst\s+(Text|SnackBar|ListTile|SwitchListTile|ElevatedButton|OutlinedButton|TextButton)\s*\(\s*(.*?context\.tr\()',
        lambda m: m.group(1) + '(' + m.group(2),
        content
    )
    
    # Fix 2: Handle multi-line cases where const is on one line and context.tr is on another
    # e.g.:
    #   const Text(
    #     context.tr('key'),
    #   )
    content = re.sub(
        r'\bconst\s+(Text|SnackBar|ListTile|SwitchListTile|ElevatedButton|OutlinedButton|TextButton)\s*\(([^)]*?\n[^)]*?context\.tr\()',
        lambda m: m.group(1) + '(' + m.group(2),
        content
    )
    
    # Fix 3: Handle const Text(context.tr(...)) inside const SnackBar
    # const SnackBar(content: Text(context.tr(...))) -> SnackBar(content: Text(context.tr(...)))
    # Already handled by Fix 1 since SnackBar is in the list
    
    if content != original:
        replacements = content.count('context.tr(') - original.count('context.tr(')
        # Actually, let's count differently
        with open(fpath, 'w', encoding='utf-8') as f:
            f.write(content)
        fixed_count += 1
        # Count actual changes
        diff_lines = 0
        orig_lines = original.split('\n')
        new_lines = content.split('\n')
        for i, (ol, nl) in enumerate(zip(orig_lines, new_lines)):
            if ol != nl:
                diff_lines += 1
        total_replacements += diff_lines
        print(f"Fixed: {os.path.relpath(fpath, D)} ({diff_lines} lines changed)")

print(f"\nDone! Fixed {fixed_count} files with {total_replacements} line changes.")
