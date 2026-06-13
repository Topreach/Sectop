#!/usr/bin/env python3
"""Check section boundaries in localization.dart"""
import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('frontend/lib/core/localization.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Check lines around the section boundaries
print("=== Lines 370-380 (end of en section) ===")
for i in range(369, 380):
    line = lines[i].rstrip()
    print(f'Line {i+1}: {line}')

print("\n=== Lines 700-715 (end of yo section) ===")
for i in range(699, 715):
    line = lines[i].rstrip()
    print(f'Line {i+1}: {line}')

print("\n=== Lines 1035-1050 (end of ig section) ===")
for i in range(1034, 1050):
    line = lines[i].rstrip()
    print(f'Line {i+1}: {line}')

print("\n=== Lines 1370-1395 (end of ha section) ===")
for i in range(1369, 1395):
    line = lines[i].rstrip()
    print(f'Line {i+1}: {line}')
