#!/usr/bin/env python3
"""Cross-reference all context.tr() keys against all 4 language sections."""
import re

# Read the localization file
with open('frontend/lib/core/localization.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Extract all keys used in context.tr() calls across all screen files
import glob
import os

all_tr_keys = set()
screen_files = glob.glob('frontend/lib/modules/**/*.dart', recursive=True)
screen_files.extend(glob.glob('frontend/lib/shared/**/*.dart', recursive=True))
screen_files.extend(glob.glob('frontend/lib/core/**/*.dart', recursive=True))

for filepath in screen_files:
    with open(filepath, 'r', encoding='utf-8') as f:
        try:
            file_content = f.read()
            keys = re.findall(r"context\.tr\('([^']+)'\)", file_content)
            all_tr_keys.update(keys)
        except:
            pass

print(f"Total unique context.tr() keys used in screens: {len(all_tr_keys)}")
print()

# Extract keys from each language section
def extract_section_keys(text, lang_code):
    """Extract all keys from a language section."""
    # Find the section
    pattern = rf"'{lang_code}':\s*\{{(.*?)\}}," 
    match = re.search(pattern, text, re.DOTALL)
    if not match:
        print(f"  WARNING: Could not find section for '{lang_code}'")
        return set()
    
    section = match.group(1)
    keys = set(re.findall(r"'([^']+)':\s*'", section))
    return keys

en_keys = extract_section_keys(content, 'en')
yo_keys = extract_section_keys(content, 'yo')
ig_keys = extract_section_keys(content, 'ig')
ha_keys = extract_section_keys(content, 'ha')

print(f"English keys: {len(en_keys)}")
print(f"Yoruba keys: {len(yo_keys)}")
print(f"Igbo keys: {len(ig_keys)}")
print(f"Hausa keys: {len(ha_keys)}")
print()

# Check which tr() keys are missing from each language
missing_in_en = all_tr_keys - en_keys
missing_in_yo = all_tr_keys - yo_keys
missing_in_ig = all_tr_keys - ig_keys
missing_in_ha = all_tr_keys - ha_keys

print("=" * 60)
print("KEYS MISSING FROM ENGLISH SECTION:")
print("=" * 60)
if missing_in_en:
    for k in sorted(missing_in_en):
        print(f"  '{k}'")
else:
    print("  None - all keys present!")
print()

print("=" * 60)
print("KEYS MISSING FROM YORUBA SECTION:")
print("=" * 60)
if missing_in_yo:
    for k in sorted(missing_in_yo):
        print(f"  '{k}'")
else:
    print("  None - all keys present!")
print()

print("=" * 60)
print("KEYS MISSING FROM IGBO SECTION:")
print("=" * 60)
if missing_in_ig:
    for k in sorted(missing_in_ig):
        print(f"  '{k}'")
else:
    print("  None - all keys present!")
print()

print("=" * 60)
print("KEYS MISSING FROM HAUSA SECTION:")
print("=" * 60)
if missing_in_ha:
    for k in sorted(missing_in_ha):
        print(f"  '{k}'")
else:
    print("  None - all keys present!")
print()

# Check for duplicate keys within each section
print("=" * 60)
print("DUPLICATE KEY CHECK:")
print("=" * 60)
for lang in ['en', 'yo', 'ig', 'ha']:
    section_match = re.search(rf"'{lang}':\s*\{{(.*?)\}},", content, re.DOTALL)
    if section_match:
        section = section_match.group(1)
        keys_list = re.findall(r"'([^']+)':\s*'", section)
        seen = {}
        dupes = []
        for k in keys_list:
            if k in seen:
                dupes.append(k)
            seen[k] = seen.get(k, 0) + 1
        if dupes:
            print(f"  {lang}: DUPLICATE KEYS FOUND: {dupes}")
        else:
            print(f"  {lang}: No duplicates")
print()

# Check for Yoruba Unicode corruption
print("=" * 60)
print("UNICODE CORRUPTION CHECK (Yoruba section):")
print("=" * 60)
yo_match = re.search(r"'yo':\s*\{(.*?)\}},", content, re.DOTALL)
if yo_match:
    yo_text = yo_match.group(1)
    # Check for corrupted patterns
    corrupted_patterns = [
        ('Ã¡', 'á (corrupted)'),
        ('Ã­', 'í (corrupted)'),
        ('á»', 'ọ (corrupted)'),
        ('áº¹', 'ẹ (corrupted)'),
        ('á¹£', 'ṣ (corrupted)'),
        ('Ã', 'Ã (any corrupted)'),
    ]
    found_corruption = False
    for pattern, desc in corrupted_patterns:
        count = yo_text.count(pattern)
        if count > 0:
            print(f"  FOUND {count}x: {desc}")
            found_corruption = True
    if not found_corruption:
        print("  No corruption found - Yoruba text is clean!")
    
    # Count proper Unicode characters
    for char, name in [('á', 'á'), ('í', 'í'), ('ọ', 'ọ'), ('ẹ', 'ẹ'), ('ṣ', 'ṣ'), ('Ṣ', 'Ṣ'), ('Ẹ', 'Ẹ'), ('Ọ', 'Ọ')]:
        count = yo_text.count(char)
        if count > 0:
            print(f"  Found {count}x proper '{char}' ({name})")

print()
print("=" * 60)
print("VERIFICATION COMPLETE")
print("=" * 60)
