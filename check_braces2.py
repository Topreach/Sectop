#!/usr/bin/env python3
import os, re
D=os.path.dirname(__file__)
P1=os.path.join(D,'frontend/lib/core/localization_part1.dart')
with open(P1,'r',encoding='utf-8-sig')as f:c=f.read()
lines=c.split('\n')
# Find all non-string braces
for i,l in enumerate(lines):
    # Remove string contents
    no_str = re.sub(r"'[^']*'", '', l)
    ob=no_str.count('{')
    cb=no_str.count('}')
    if ob>0 or cb>0:
        print(f"Line {i+1}: opens={ob} closes={cb} -> {l.strip()[:80]}")
