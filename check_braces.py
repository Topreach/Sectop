#!/usr/bin/env python3
import os
D=os.path.dirname(__file__)
P=os.path.join(D,'frontend/lib/core/localization.dart')
with open(P,'r',encoding='utf-8')as f:c=f.read()
opens=c.count('{')
closes=c.count('}')
print(f"localization.dart: {opens} opens, {closes} closes, balanced={opens==closes}")
# Check part1
P1=os.path.join(D,'frontend/lib/core/localization_part1.dart')
with open(P1,'r',encoding='utf-8-sig')as f:c1=f.read()
o1=c1.count('{')
c1c=c1.count('}')
print(f"part1: {o1} opens, {c1c} closes, balanced={o1==c1c}")
# Find braces in string values in localization.dart
import re
# Count braces that are NOT inside string values
# Simple approach: remove all string values and count
no_strings = re.sub(r"'[^']*'", '', c)
real_opens = no_strings.count('{')
real_closes = no_strings.count('}')
print(f"Real (non-string) braces: {real_opens} opens, {real_closes} closes, balanced={real_opens==real_closes}")
