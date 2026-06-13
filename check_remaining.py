#!/usr/bin/env python3
"""Check specific lines that still appear corrupted in the display."""
with open('frontend/lib/core/localization.dart', 'rb') as f:
    raw = f.read()

# Check line 460: 'á¹¢e apejuwe'
# Search for 'apejuwe'
idx = raw.find(b'apejuwe')
if idx >= 0:
    chunk = raw[idx-10:idx+20]
    print(f"Line 460 context: {chunk.hex()}")
    print(f"Line 460 text: {chunk}")

# Check line 463: 'Jáº¹Ì kÃ­ o fọkÃ n'
idx = raw.find(b'J')
if idx >= 0:
    # Find 'Jáº¹' pattern
    for i in range(len(raw)-5):
        if raw[i:i+1] == b'J' and raw[i+1:i+2] in [0xC3, 0xE1]:
            chunk = raw[i:i+60]
            if b'f' in chunk:
                print(f"\nJ... context at {i}: {chunk.hex()}")
                print(f"J... text: {chunk}")
                break

# Check line 465: 'áº¸ri'
idx = raw.find(b'ri Kun')
if idx >= 0:
    chunk = raw[idx-15:idx+10]
    print(f"\nLine 465 context: {chunk.hex()}")
    print(f"Line 465 text: {chunk}")

# Check line 469: 'áº¸ri Ti'
idx = raw.find(b'ri Ti Ya')
if idx >= 0:
    chunk = raw[idx-15:idx+10]
    print(f"\nLine 469 context: {chunk.hex()}")
    print(f"Line 469 text: {chunk}")

# Check line 474: 'á»Œrọigbaniwọle'
idx = raw.find(b'r')
if idx >= 0:
    for i in range(len(raw)-20):
        if raw[i:i+8] == b'r\xe1\xbb\x8digbaniw\xe1\xbb\x8dle':
            chunk = raw[i-10:i+25]
            print(f"\nLine 474 context: {chunk.hex()}")
            print(f"Line 474 text: {chunk}")
            break

# Also check for any non-ASCII bytes that might still be corrupted
# Look for bytes that appear in the Yoruba section but aren't the correct patterns
print("\n--- All unique non-ASCII byte sequences in file ---")
non_ascii_seqs = set()
i = 0
while i < len(raw):
    if raw[i] > 127:
        seq = []
        while i < len(raw) and raw[i] > 127:
            seq.append(raw[i])
            i += 1
        if len(seq) >= 2:
            non_ascii_seqs.add(bytes(seq))
    else:
        i += 1

for seq in sorted(non_ascii_seqs, key=lambda x: len(x)):
    count = raw.count(seq)
    if count > 0:
        try:
            text = seq.decode('utf-8')
            print(f"  {seq.hex():20s} x{count:4d} = '{text}'")
        except:
            print(f"  {seq.hex():20s} x{count:4d} = INVALID UTF-8!")
