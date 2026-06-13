#!/usr/bin/env python3
"""Analyze and fix double-encoded Unicode in localization.dart."""
import sys

filepath = 'frontend/lib/core/localization.dart'

with open(filepath, 'rb') as f:
    raw = f.read()

print(f"File size: {len(raw)} bytes")

# Find the Yoruba section - look for 'send_sos_alert'
idx = raw.find(b'send_sos_alert')
if idx >= 0:
    print(f"Found 'send_sos_alert' at byte offset: {idx}")
    chunk = raw[idx:idx+100]
    print(f"Raw bytes hex: {chunk.hex()}")
    print(f"Raw bytes repr: {repr(chunk)}")
else:
    print("'send_sos_alert' NOT found in raw bytes")
    # Try searching for 'RÃ¡n' - the corrupted version
    idx2 = raw.find(b'R')
    print(f"First 'R' at: {idx2}")
    # Show bytes around that area
    if idx2 >= 0:
        chunk2 = raw[idx2:idx2+50]
        print(f"Bytes around first R: {chunk2.hex()}")
        print(f"Repr: {repr(chunk2)}")

# Also check what encoding the file actually is
print("\n--- Checking encoding ---")
# Try decoding as UTF-8
try:
    text = raw.decode('utf-8')
    print("File is valid UTF-8")
    # Look for mojibake patterns
    patterns = ['Ã¡', 'Ã©', 'Ã­', 'Ã³', 'Ãº', 'Ã±', 'á»', 'áº¹', 'á¹£']
    for p in patterns:
        count = text.count(p)
        if count > 0:
            print(f"  Found mojibake '{p}': {count} occurrences")
except UnicodeDecodeError as e:
    print(f"File is NOT valid UTF-8: {e}")

# Check if it's Latin-1
try:
    text_latin1 = raw.decode('latin-1')
    print("File is valid Latin-1")
except:
    print("File is NOT valid Latin-1")
