#!/usr/bin/env python3
"""
Fix double-encoded Unicode in localization.dart using direct byte replacement.

The file has mixed encoding: English section is correct UTF-8, but Yoruba/Igbo/Hausa
sections have double-encoded characters.

Corruption pattern:
  Original byte (UTF-8) -> Interpreted as Latin-1 -> Encoded as UTF-8 again
  \xc3\xa1 (á) -> Ã (U+00C3) + ¡ (U+00A1) -> \xc3\x83\xc2\xa1

Fix: Replace the double-encoded byte sequences with the correct single-encoded ones.
"""
import sys

filepath = 'frontend/lib/core/localization.dart'

with open(filepath, 'rb') as f:
    raw = f.read()

print(f"Original file size: {len(raw)} bytes")

# Define replacements: corrupted_bytes -> correct_bytes
replacements = {
    # á (a with acute) = U+00E1, correct UTF-8: C3 A1
    # Corrupted: Ã (C3) + ¡ (A1) -> C3 83 C2 A1
    bytes([0xC3, 0x83, 0xC2, 0xA1]): bytes([0xC3, 0xA1]),
    
    # í (i with acute) = U+00ED, correct UTF-8: C3 AD
    # Corrupted: Ã (C3) + (AD) -> C3 83 C2 AD
    bytes([0xC3, 0x83, 0xC2, 0xAD]): bytes([0xC3, 0xAD]),
    
    # ọ (o with dot below) = U+1ECD, correct UTF-8: E1 BB 8D
    # Corrupted: á (E1) + » (BB) +  (8D) -> C3 A1 C2 BB C2 8D
    bytes([0xC3, 0xA1, 0xC2, 0xBB, 0xC2, 0x8D]): bytes([0xE1, 0xBB, 0x8D]),
    
    # ẹ (e with dot below) = U+1EB9, correct UTF-8: E1 BA B9
    # Corrupted: á (E1) + º (BA) + ¹ (B9) -> C3 A1 C2 BA C2 B9
    bytes([0xC3, 0xA1, 0xC2, 0xBA, 0xC2, 0xB9]): bytes([0xE1, 0xBA, 0xB9]),
    
    # ṣ (s with dot below) = U+1E63, correct UTF-8: E1 B9 A3
    # Corrupted: á (E1) + ¹ (B9) + £ (A3) -> C3 A1 C2 B9 C2 A3
    bytes([0xC3, 0xA1, 0xC2, 0xB9, 0xC2, 0xA3]): bytes([0xE1, 0xB9, 0xA3]),
}

total_replaced = 0
for corrupted, correct in replacements.items():
    count = raw.count(corrupted)
    if count > 0:
        raw = raw.replace(corrupted, correct)
        total_replaced += count
        print(f"  Replaced {count} occurrences of {corrupted.hex()} -> {correct.hex()}")

print(f"\nTotal replacements: {total_replaced}")

# Write the fixed file
with open(filepath, 'wb') as f:
    f.write(raw)

print(f"Fixed file size: {len(raw)} bytes")

# Verify
print("\n--- Verification ---")
try:
    text = raw.decode('utf-8')
    print("File is valid UTF-8 ✓")
    
    # Check for remaining corrupted patterns
    remaining = 0
    for corrupted, _ in replacements.items():
        if corrupted in raw:
            c = raw.count(corrupted)
            print(f"  WARNING: Still has {corrupted.hex()}: {c} occurrences")
            remaining += c
    
    if remaining == 0:
        print("  No remaining corrupted byte patterns ✓")
    else:
        print(f"  {remaining} corrupted patterns still present")
        
    # Check for correct patterns
    for name, correct_bytes in [
        ('á', bytes([0xC3, 0xA1])),
        ('í', bytes([0xC3, 0xAD])),
        ('ọ', bytes([0xE1, 0xBB, 0x8D])),
        ('ẹ', bytes([0xE1, 0xBA, 0xB9])),
        ('ṣ', bytes([0xE1, 0xB9, 0xA3])),
    ]:
        c = raw.count(correct_bytes)
        print(f"  Correct '{name}': {c} occurrences")
        
except UnicodeDecodeError as e:
    print(f"File is NOT valid UTF-8: {e}")
    sys.exit(1)
