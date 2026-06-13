#!/usr/bin/env python3
"""
Fix ALL double-encoded Unicode in localization.dart using direct byte replacement.

Phase 1 fixed the most common patterns (á, í, ọ, ẹ, ṣ).
Phase 2 fixes the remaining patterns (Ṣ, Ẹ, Ọ, à, ò, ù, etc.)
"""
import sys

filepath = 'frontend/lib/core/localization.dart'

with open(filepath, 'rb') as f:
    raw = f.read()

print(f"Original file size: {len(raw)} bytes")

# Define ALL replacements: corrupted_bytes -> correct_bytes
replacements = {
    # Phase 1 patterns (already fixed, but include for completeness)
    # á (a with acute) = U+00E1
    bytes([0xC3, 0x83, 0xC2, 0xA1]): bytes([0xC3, 0xA1]),
    # í (i with acute) = U+00ED
    bytes([0xC3, 0x83, 0xC2, 0xAD]): bytes([0xC3, 0xAD]),
    # ọ (o with dot below) = U+1ECD
    bytes([0xC3, 0xA1, 0xC2, 0xBB, 0xC2, 0x8D]): bytes([0xE1, 0xBB, 0x8D]),
    # ẹ (e with dot below) = U+1EB9
    bytes([0xC3, 0xA1, 0xC2, 0xBA, 0xC2, 0xB9]): bytes([0xE1, 0xBA, 0xB9]),
    # ṣ (s with dot below) = U+1E63
    bytes([0xC3, 0xA1, 0xC2, 0xB9, 0xC2, 0xA3]): bytes([0xE1, 0xB9, 0xA3]),
    
    # Phase 2 patterns:
    # Ṣ (capital S with dot below) = U+1E62, correct: E1 B9 A2
    # Corrupted: á (E1) + ¹ (B9) + ¢ (A2) -> C3 A1 C2 B9 C2 A2
    bytes([0xC3, 0xA1, 0xC2, 0xB9, 0xC2, 0xA2]): bytes([0xE1, 0xB9, 0xA2]),
    
    # Ẹ (capital E with dot below) = U+1EB8, correct: E1 BA B8
    # Corrupted: á (E1) + º (BA) + ¸ (B8) -> C3 A1 C2 BA C2 B8
    bytes([0xC3, 0xA1, 0xC2, 0xBA, 0xC2, 0xB8]): bytes([0xE1, 0xBA, 0xB8]),
    
    # Ọ (capital O with dot below) = U+1ECC, correct: E1 BB 8C
    # Corrupted: á (E1) + » (BB) + Œ (C5 92) -> C3 A1 C2 BB C5 92
    bytes([0xC3, 0xA1, 0xC2, 0xBB, 0xC5, 0x92]): bytes([0xE1, 0xBB, 0x8C]),
    
    # à (a with grave) = U+00E0, correct: C3 A0
    # Corrupted: Ã (C3) + (A0) -> C3 83 C2 A0
    bytes([0xC3, 0x83, 0xC2, 0xA0]): bytes([0xC3, 0xA0]),
    
    # ò (o with grave) = U+00F2, correct: C3 B2
    # Corrupted: Ã (C3) + ò (C2 B2) -> C3 83 C2 B2
    bytes([0xC3, 0x83, 0xC2, 0xB2]): bytes([0xC3, 0xB2]),
    
    # ù (u with grave) = U+00F9, correct: C3 B9
    # Corrupted: Ã (C3) + ù (C2 B9) -> C3 83 C2 B9
    bytes([0xC3, 0x83, 0xC2, 0xB9]): bytes([0xC3, 0xB9]),
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
        c = raw.count(corrupted)
        if c > 0:
            print(f"  WARNING: Still has {corrupted.hex()}: {c} occurrences")
            remaining += c
    
    if remaining == 0:
        print("  No remaining corrupted byte patterns ✓")
    else:
        print(f"  {remaining} corrupted patterns still present")
        
except UnicodeDecodeError as e:
    print(f"File is NOT valid UTF-8: {e}")
    sys.exit(1)
