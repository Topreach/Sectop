#!/usr/bin/env python3
"""Analyze the actual byte patterns in localization.dart."""
import sys

filepath = 'frontend/lib/core/localization.dart'

with open(filepath, 'rb') as f:
    raw = f.read()

print(f"File size: {len(raw)} bytes")

# The file shows 'RÃ¡n' in the Yoruba section for 'send_sos_alert'
# Let's find the Yoruba section by looking for 'Fi Itaniji'
idx = raw.find(b'Fi Itaniji')
if idx >= 0:
    print(f"\nFound 'Fi Itaniji' at byte {idx}")
    chunk = raw[idx:idx+80]
    print(f"Hex: {chunk.hex()}")
    print(f"Repr: {repr(chunk)}")
    
    # Show each byte
    print("\nByte-by-byte:")
    for i, b in enumerate(chunk):
        c = chr(b) if 32 <= b <= 126 else '.'
        print(f"  [{i:3d}] 0x{b:02x} ({c})")
else:
    print("'Fi Itaniji' not found")

# Also find 'Awá»n' which appears in the Yoruba section
idx2 = raw.find(b'Aw')
if idx2 >= 0:
    print(f"\nFound 'Aw' at byte {idx2}")
    chunk2 = raw[idx2:idx2+50]
    print(f"Hex: {chunk2.hex()}")
    print(f"Repr: {repr(chunk2)}")
    
    print("\nByte-by-byte:")
    for i, b in enumerate(chunk2):
        c = chr(b) if 32 <= b <= 126 else '.'
        print(f"  [{i:3d}] 0x{b:02x} ({c})")

# Check for the specific mojibake patterns
print("\n--- Searching for mojibake byte patterns ---")

# 'Ã¡' - this is what we see displayed. In UTF-8:
# 'Ã' = C3 83, '¡' = C2 A1
# So 'Ã¡' as bytes = C3 83 C2 A1
pattern1 = bytes([0xC3, 0x83, 0xC2, 0xA1])
count1 = raw.count(pattern1)
print(f"Pattern Ã¡ (C3 83 C2 A1): {count1} occurrences")

# 'á»' - what we see displayed
# 'á' = C3 A1, '»' = C2 BB, '' = C2 8D
pattern2 = bytes([0xC3, 0xA1, 0xC2, 0xBB, 0xC2, 0x8D])
count2 = raw.count(pattern2)
print(f"Pattern á» (C3 A1 C2 BB C2 8D): {count2} occurrences")

# 'áº¹' - what we see displayed
# 'á' = C3 A1, 'º' = C2 BA, '¹' = C2 B9
pattern3 = bytes([0xC3, 0xA1, 0xC2, 0xBA, 0xC2, 0xB9])
count3 = raw.count(pattern3)
print(f"Pattern áº¹ (C3 A1 C2 BA C2 B9): {count3} occurrences")

# 'á¹£' - what we see displayed
# 'á' = C3 A1, '¹' = C2 B9, '£' = C2 A3
pattern4 = bytes([0xC3, 0xA1, 0xC2, 0xB9, 0xC2, 0xA3])
count4 = raw.count(pattern4)
print(f"Pattern á¹£ (C3 A1 C2 B9 C2 A3): {count4} occurrences")

# 'Ã©' - e with acute corrupted
pattern5 = bytes([0xC3, 0x83, 0xC2, 0xA9])
count5 = raw.count(pattern5)
print(f"Pattern Ã© (C3 83 C2 A9): {count5} occurrences")

# 'Ã­' - i with acute corrupted
pattern6 = bytes([0xC3, 0x83, 0xC2, 0xAD])
count6 = raw.count(pattern6)
print(f"Pattern Ã­ (C3 83 C2 AD): {count6} occurrences")

# 'Ã³' - o with acute corrupted
pattern7 = bytes([0xC3, 0x83, 0xC2, 0xB3])
count7 = raw.count(pattern7)
print(f"Pattern Ã³ (C3 83 C2 B3): {count7} occurrences")

# 'Ãº' - u with acute corrupted
pattern8 = bytes([0xC3, 0x83, 0xC2, 0xBA])
count8 = raw.count(pattern8)
print(f"Pattern Ãº (C3 83 C2 BA): {count8} occurrences")

# 'Ã±' - n with tilde corrupted
pattern9 = bytes([0xC3, 0x83, 0xC2, 0xB1])
count9 = raw.count(pattern9)
print(f"Pattern Ã± (C3 83 C2 B1): {count9} occurrences")

# Also check for the single-byte corruption pattern
# Where the original UTF-8 bytes were just stored as Latin-1
# e.g., á (U+00E1) = byte 0xE1 in Latin-1
# But in UTF-8, 0xE1 is the start of a 3-byte sequence
# So if the file has raw Latin-1 bytes, it would fail UTF-8 decoding
# Since it decodes as UTF-8 successfully, the bytes are valid UTF-8
# This means the corruption is double-encoding

print("\n--- Summary ---")
total = count1 + count2 + count3 + count4 + count5 + count6 + count7 + count8 + count9
print(f"Total mojibake occurrences: {total}")
