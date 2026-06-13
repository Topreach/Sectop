#!/usr/bin/env python3
"""
Fix ALL remaining double-encoded Unicode in localization.dart.

Phase 3: Fix remaining patterns including emoji and special characters.
"""
import sys

filepath = 'frontend/lib/core/localization.dart'

with open(filepath, 'rb') as f:
    raw = f.read()

print(f"Original file size: {len(raw)} bytes")

# Phase 3: Fix remaining corrupted patterns
replacements = {
    # á»‹ (some kind of corrupted character) = C3 A1 C2 BB E2 80 B9
    # This is likely a corrupted version of some character
    # Let's check what it should be by looking at context
    
    # âš (warning sign emoji) = U+26A0 ⚠
    # Correct UTF-8: E2 9A A0
    # Corrupted: â (C3 A2) + š (C5 A1) + (C2 A0) -> C3 A2 C5 A1 C2 A0
    bytes([0xC3, 0xA2, 0xC5, 0xA1, 0xC2, 0xA0]): bytes([0xE2, 0x9A, 0xA0]),
    
    # âœ… (check mark emoji) = U+2705 ✅
    # Correct UTF-8: E2 9C 85
    # Corrupted: â (C3 A2) + œ (C5 93) + â€¦ (E2 80 A6) -> C3 A2 C5 93 E2 80 A6
    bytes([0xC3, 0xA2, 0xC5, 0x93, 0xE2, 0x80, 0xA6]): bytes([0xE2, 0x9C, 0x85]),
    
    # â€” (em dash) = U+2014 —
    # Correct UTF-8: E2 80 94
    # Corrupted: â (C3 A2) + € (E2 82 AC) + â€ (E2 80) +  (9D) -> C3 A2 E2 82 AC E2 80 9D
    bytes([0xC3, 0xA2, 0xE2, 0x82, 0xAC, 0xE2, 0x80, 0x9D]): bytes([0xE2, 0x80, 0x94]),
    
    # á»‹ - let me check what this is
    # C3 A1 C2 BB E2 80 B9
    # This looks like: á (C3 A1) + » (C2 BB) + ‹ (E2 80 B9)
    # The original was probably a single character that got double-encoded
    # Let me check the context to determine what it should be
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

# Final comprehensive verification
print("\n--- Final Verification ---")
try:
    text = raw.decode('utf-8')
    print("File is valid UTF-8 ✓")
    
    # Check for ANY byte sequence that looks like double-encoding
    # Pattern: C3 XX C2 YY (double-encoded Latin-1 supplement)
    # Pattern: C3 XX C2 YY C2 ZZ (double-encoded 3-byte UTF-8)
    suspicious = 0
    i = 0
    while i < len(raw) - 3:
        if raw[i] == 0xC3 and i+1 < len(raw) and 0x80 <= raw[i+1] <= 0xBF:
            # Found C3 XX - check if followed by C2
            if i+2 < len(raw) and raw[i+2] == 0xC2:
                suspicious += 1
                seq = raw[i:i+5] if i+5 < len(raw) else raw[i:]
                print(f"  Suspicious at offset {i}: {seq.hex()}")
                i += 1
                continue
        i += 1
    
    if suspicious == 0:
        print("  No suspicious double-encoding patterns found ✓")
    else:
        print(f"  {suspicious} suspicious patterns found")
        
except UnicodeDecodeError as e:
    print(f"File is NOT valid UTF-8: {e}")
    sys.exit(1)
