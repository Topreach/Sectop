#!/usr/bin/env python3
"""Fix localization.dart - read part1, fix truncation, append remaining content."""
import os

D = os.path.dirname(__file__)
P1 = os.path.join(D, 'frontend', 'lib', 'core', 'localization_part1.dart')
OUT = os.path.join(D, 'frontend', 'lib', 'core', 'localization.dart')

with open(P1, 'r', encoding='utf-8') as f:
    c = f.read()

# Fix truncated line - the file has 'J\u1ecdw\u1ecd t' at end
# We need to complete it and add all remaining content
old = "'please_enter_phone': 'J\u1ecdw\u1ecd t"
new = "'please_enter_phone': 'J\u1ecdw\u1ecd t\u1eb9 n\u1ecdmba foonu r\u1eb9 sii',"
c = c.replace(old, new)

# Find the last complete line
lines = c.split('\n')
idx = -1
for i, l in enumerate(lines):
    if 'please_enter_phone' in l:
        idx = i
        break

# Keep everything up to and including the fixed line
base_lines = lines[:idx+1]

# Now we need to add:
# 1. Remaining Yoruba keys (from please_enter_password to permission_storage)
# 2. Complete Igbo translations
# 3. Complete Hausa translations
# 4. Close _localizedValues
# 5. _AppLocalizationsDelegate class
# 6. AppLocalizationsX extension

# Instead of embedding all translations here (too large),
# let's generate the complete file by reading the existing localization.dart
# and appending the missing parts

# The key insight: we need to write the COMPLETE file
# Let's use a different strategy - write it in parts

# First, write the fixed base
with open(OUT, 'w', encoding='utf-8') as f:
    f.write('\n'.join(base_lines))
    f.write('\n')

print(f"Fixed base written: {len(base_lines)} lines")
print(f"File size: {os.path.getsize(OUT)} bytes")
