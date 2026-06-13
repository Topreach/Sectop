#!/usr/bin/env python3
import os, re
D=os.path.dirname(__file__)
P=os.path.join(D,'frontend/lib/core/localization.dart')
with open(P,'r',encoding='utf-8')as f:c=f.read()
lines=c.split('\n')
for i,l in enumerate(lines):
    no_str = re.sub(r"'[^']*'", '', l)
    ob=no_str.count('{')
    cb=no_str.count('}')
    if ob>0 or cb>0:
        print(f"Line {i+1}: opens={ob} closes={cb} -> {l.strip()[:100]}")
