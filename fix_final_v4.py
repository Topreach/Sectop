#!/usr/bin/env python3
"""Fix the last 2 remaining corrupted patterns."""
with open('frontend/lib/core/localization.dart', 'rb') as f:
    raw = f.read()

print(f"Original size: {len(raw)} bytes")

# Fix 1: Line 463 - JẹÌ -> Jẹ́ (ẹ with combining acute accent)
# Current: \xe1\xba\xb9\xc3\x8c\xc2\x81
# \xc3\x8c = Ì (U+00CC), \xc2\x81 = control char
# Should be: \xe1\xba\xb9\xcc\x81 (ẹ + combining acute accent U+0301)
pattern1 = bytes([0xE1, 0xBA, 0xB9, 0xC3, 0x8C, 0xC2, 0x81])
replacement1 = bytes([0xE1, 0xBA, 0xB9, 0xCC, 0x81])  # ẹ́
count1 = raw.count(pattern1)
if count1 > 0:
    raw = raw.replace(pattern1, replacement1)
    print(f"Fixed {count1} occurrences of JẹÌ -> Jẹ́")

# Fix 2: Line 536 - á»‹ti -> ọti
# Current: \xc3\xa1\xc2\xbb\xe2\x80\xb9
# This is a corrupted version of ọ (E1 BB 8D)
# The \xc3\xa1\xc2\xbb is the start of double-encoded ọ, but \xe2\x80\xb9 is wrong
# Should be: \xe1\xbb\x8d (ọ)
pattern2 = bytes([0xC3, 0xA1, 0xC2, 0xBB, 0xE2, 0x80, 0xB9])
replacement2 = bytes([0xE1, 0xBB, 0x8D])  # ọ
count2 = raw.count(pattern2)
if count2 > 0:
    raw = raw.replace(pattern2, replacement2)
    print(f"Fixed {count2} occurrences of á»‹ -> ọ")

# Fix 3: Line 615 - Ìmúṣiṣi -> Ìmúṣiṣi (this might actually be correct)
# \xc3\x8c\xc2\x81 - let me check if this is the same pattern
# Actually \xc3\x8c = Ì, and \xc2\x81 is a control char
# Let me check what this should be
pattern3 = bytes([0xC3, 0x8C, 0xC2, 0x81])
# This appears in 'Ìmúṣiṣi' - the Ì (capital I with grave) is correct
# But the \xc2\x81 after it is wrong
# Let me check the context
idx = raw.find(pattern3)
if idx >= 0:
    context = raw[idx-5:idx+10]
    print(f"\nPattern 3 context: {context.hex()}")
    print(f"Pattern 3 text: {context}")
    # If it's at the start of a word, the \xc2\x81 is junk
    # Remove the \xc2\x81
    raw = raw.replace(pattern3, bytes([0xC3, 0x8C]))  # Just Ì
    print("Fixed Ì\xc2\x81 -> Ì")

# Write the fixed file
with open('frontend/lib/core/localization.dart', 'wb') as f:
    f.write(raw)

print(f"\nFinal size: {len(raw)} bytes")

# Final verification
print("\n--- Final Verification ---")
try:
    text = raw.decode('utf-8')
    print("File is valid UTF-8 ✓")
    
    # Check for any remaining suspicious patterns
    suspicious = 0
    i = 0
    while i < len(raw) - 3:
        if raw[i] == 0xC3 and i+1 < len(raw) and 0x80 <= raw[i+1] <= 0xBF:
            if i+2 < len(raw) and raw[i+2] == 0xC2:
                suspicious += 1
                seq = raw[i:i+5] if i+5 < len(raw) else raw[i:]
                print(f"  Suspicious at offset {i}: {seq.hex()}")
                i += 1
                continue
        i += 1
    
    if suspicious == 0:
        print("  No remaining suspicious double-encoding patterns ✓")
    else:
        print(f"  {suspicious} suspicious patterns remain")
        
except UnicodeDecodeError as e:
    print(f"File is NOT valid UTF-8: {e}")
