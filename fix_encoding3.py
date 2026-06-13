#!/usr/bin/env python3
"""
Fix double-encoded Unicode in localization.dart using byte-level replacement.

The file has mixed encoding: English section is correct UTF-8, but Yoruba/Igbo/Hausa
sections have double-encoded characters where UTF-8 bytes were interpreted as Latin-1.

For example:
  'á' (U+00E1) = UTF-8 bytes C3 A1
  When saved as Latin-1: Ã (C3) + ¡ (A1) → 'Ã¡'
  
  'á»' = UTF-8 bytes C3 A1 E1 BB 8D
  When saved as Latin-1: Ã (C3) + ¡ (A1) + á (E1) + » (BB) +  (8D) → 'á»'

The fix: find these corrupted byte sequences and replace them with the correct UTF-8.
"""
import re

filepath = 'frontend/lib/core/localization.dart'

with open(filepath, 'rb') as f:
    raw = f.read()

print(f"Original file size: {len(raw)} bytes")

# Build a mapping of corrupted byte sequences -> correct UTF-8 bytes
# The corruption pattern: correct UTF-8 bytes were read as Latin-1 characters,
# then those Latin-1 characters were encoded as UTF-8 again.
# So to fix: we need to find the double-encoded sequences and replace them.

# Common Yoruba/Igbo/Hausa characters and their double-encoded forms:
# Correct char -> UTF-8 bytes -> Latin-1 interpretation -> UTF-8 re-encoding
replacements = {}

# Yoruba: á (a with acute) = U+00E1
# UTF-8: C3 A1
# Latin-1: Ã (C3) + ¡ (A1)
# Double-encoded: C3 83 C2 A1
replacements[b'\xc3\x83\xc2\xa1'] = b'\xc3\xa1'  # á

# Yoruba: é (e with acute) = U+00E9
replacements[b'\xc3\x83\xc2\xa9'] = b'\xc3\xa9'  # é

# Yoruba: í (i with acute) = U+00ED
replacements[b'\xc3\x83\xc2\xad'] = b'\xc3\xad'  # í

# Yoruba: ó (o with acute) = U+00F3
replacements[b'\xc3\x83\xc2\xb3'] = b'\xc3\xb3'  # ó

# Yoruba: ú (u with acute) = U+00FA
replacements[b'\xc3\x83\xc2\xba'] = b'\xc3\xba'  # ú

# Yoruba: ñ (n with tilde) = U+00F1
replacements[b'\xc3\x83\xc2\xb1'] = b'\xc3\xb1'  # ñ

# Yoruba: ọ (o with dot below) = U+1ECD
# UTF-8: E1 BB 8D
# Latin-1: á (E1) + » (BB) +  (8D)
# Double-encoded: C3 A1 C2 BB C2 8D
replacements[b'\xc3\xa1\xc2\xbb\xc2\x8d'] = b'\xe1\xbb\x8d'  # ọ

# Yoruba: ẹ (e with dot below) = U+1EB9
# UTF-8: E1 BA B9
# Latin-1: á (E1) + º (BA) + ¹ (B9)
# Double-encoded: C3 A1 C2 BA C2 B9
replacements[b'\xc3\xa1\xc2\xba\xc2\xb9'] = b'\xe1\xba\xb9'  # ẹ

# Yoruba: ṣ (s with dot below) = U+1E63
# UTF-8: E1 B9 A3
# Latin-1: á (E1) + ¹ (B9) + £ (A3)
# Double-encoded: C3 A1 C2 B9 C2 A3
replacements[b'\xc3\xa1\xc2\xb9\xc2\xa3'] = b'\xe1\xb9\xa3'  # ṣ

# Also handle the case where only some bytes are double-encoded
# Check for patterns like Ã¡ (which is C3 83 C2 A1 in UTF-8)
# Actually let me check what's actually in the file

# Let me search for the actual byte patterns
for pattern_bytes, replacement in replacements.items():
    count = raw.count(pattern_bytes)
    if count > 0:
        print(f"  Pattern {pattern_bytes.hex()}: {count} occurrences -> replacing")

# Count total replacements
total = 0
for pattern_bytes, replacement in replacements.items():
    count = raw.count(pattern_bytes)
    if count > 0:
        raw = raw.replace(pattern_bytes, replacement)
        total += count

print(f"Total replacements made: {total}")

# Write the fixed file
with open(filepath, 'wb') as f:
    f.write(raw)

print(f"Fixed file size: {len(raw)} bytes")

# Verify
print("\n--- Verification ---")
try:
    text = raw.decode('utf-8')
    print("File is valid UTF-8 ✓")
    
    # Check for remaining mojibake
    remaining = 0
    for p in ['Ã¡', 'Ã©', 'Ã­', 'Ã³', 'Ãº', 'Ã±', 'á»', 'áº¹', 'á¹£']:
        c = text.count(p)
        if c > 0:
            print(f"  WARNING: Still has '{p}': {c} occurrences")
            remaining += c
    if remaining == 0:
        print("  No remaining mojibake patterns found ✓")
    else:
        print(f"  {remaining} mojibake patterns still present")
except UnicodeDecodeError as e:
    print(f"File is NOT valid UTF-8: {e}")
