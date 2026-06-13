#!/usr/bin/env python3
"""Check if the fix was applied correctly."""
with open('frontend/lib/core/localization.dart', 'rb') as f:
    raw = f.read()

# Check for the corrupted patterns
p1 = raw.count(bytes([0xC3, 0x83, 0xC2, 0xA1]))  # Ã¡
p2 = raw.count(bytes([0xC3, 0xA1, 0xC2, 0xBB, 0xC2, 0x8D]))  # á»
p3 = raw.count(bytes([0xC3, 0xA1, 0xC2, 0xBA, 0xC2, 0xB9]))  # áº¹
p4 = raw.count(bytes([0xC3, 0xA1, 0xC2, 0xB9, 0xC2, 0xA3]))  # á¹£
p5 = raw.count(bytes([0xC3, 0x83, 0xC2, 0xAD]))  # Ã­

print(f'Corrupted patterns remaining:')
print(f'  Ã¡ (C3 83 C2 A1): {p1}')
print(f'  á» (C3 A1 C2 BB C2 8D): {p2}')
print(f'  áº¹ (C3 A1 C2 BA C2 B9): {p3}')
print(f'  á¹£ (C3 A1 C2 B9 C2 A3): {p4}')
print(f'  Ã­ (C3 83 C2 AD): {p5}')

# Check for the correct patterns
c1 = raw.count(bytes([0xC3, 0xA1]))  # á
c2 = raw.count(bytes([0xE1, 0xBB, 0x8D]))  # ọ
c3 = raw.count(bytes([0xE1, 0xBA, 0xB9]))  # ẹ
c4 = raw.count(bytes([0xE1, 0xB9, 0xA3]))  # ṣ

print(f'\nCorrect patterns:')
print(f'  á (C3 A1): {c1}')
print(f'  ọ (E1 BB 8D): {c2}')
print(f'  ẹ (E1 BA B9): {c3}')
print(f'  ṣ (E1 B9 A3): {c4}')

# Check the Yoruba section for 'send_sos_alert'
idx = raw.find(b"send_sos_alert")
if idx >= 0:
    # Find the Yoruba version (second occurrence)
    idx2 = raw.find(b"send_sos_alert", idx + 50)
    if idx2 >= 0:
        chunk = raw[idx2:idx2+60]
        print(f'\nYoruba send_sos_alert bytes: {chunk.hex()}')
        print(f'Yoruba send_sos_alert text: {chunk}')
    else:
        print('\nOnly one send_sos_alert found (English only?)')
else:
    print('\nsend_sos_alert not found at all!')
