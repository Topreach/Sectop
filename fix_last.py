#!/usr/bin/env python3
"""Fix the last 2 suspicious patterns."""
with open('frontend/lib/core/localization.dart', 'rb') as f:
    raw = f.read()

# Suspicious at offset 20585: c38cc28120
# C3 8C C2 81 20
# C3 8C = Ì (U+00CC, I with grave)
# C2 81 = (U+0081, control character - this is wrong!)
# This is double-encoded: Ì (C3 8C) should just be C3 8C
# The C2 81 is extra junk
# Let's see the context
print("Offset 20585 context:")
chunk = raw[20570:20610]
print(f"  Hex: {chunk.hex()}")
print(f"  Text: {chunk}")

# Suspicious at offset 24021: c3a1c2bbe2
# C3 A1 C2 BB E2
# This is á» + start of another sequence
# Let's see the context
print("\nOffset 24021 context:")
chunk2 = raw[24010:24050]
print(f"  Hex: {chunk2.hex()}")
print(f"  Text: {chunk2}")

# Also check what the full context around these is
# Find the line containing these
text = raw.decode('utf-8')
lines = text.split('\n')
for i, line in enumerate(lines):
    if 'Ì' in line and i > 0:
        print(f"\nLine {i+1}: {line.strip()}")
    if 'á»' in line:
        print(f"\nLine {i+1}: {line.strip()}")
