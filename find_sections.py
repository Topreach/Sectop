#!/usr/bin/env python3
"""Find section boundaries in localization.dart"""
with open('frontend/lib/core/localization.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f'Total lines: {len(lines)}')

# Find section boundaries
for i, line in enumerate(lines):
    s = line.strip()
    if s in ["'en': {", "'yo': {", "'ig': {", "'ha': {"]:
        print(f'Line {i+1}: SECTION START {s}')
    elif s == '};' and i > 0:
        print(f'Line {i+1}: CLOSE }};')
    elif s == '}' and i > 0 and lines[i-1].strip().endswith("',"):
        print(f'Line {i+1}: SECTION END }}')
