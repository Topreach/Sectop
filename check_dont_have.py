#!/usr/bin/env python3
"""Check dont_have_account_register key in all sections"""
import re

with open('frontend/lib/core/localization.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Check en section (lines 20-374, 0-indexed 19-373)
en_text = ''.join(lines[19:373])
keys = re.findall(r"'(\w+)':\s*'", en_text)
print(f'en section: {len(keys)} keys')
print(f"  'dont_have_account_register' in en: {'dont_have_account_register' in keys}")
for k in keys:
    if 'dont_have' in k or 'already_have' in k:
        print(f'  Found key: {k}')

# Check ig section (lines 709-1041, 0-indexed 708-1040)
ig_text = ''.join(lines[708:1040])
keys_ig = re.findall(r"'(\w+)':\s*'", ig_text)
print(f'\nig section: {len(keys_ig)} keys')
print(f"  'dont_have_account_register' in ig: {'dont_have_account_register' in keys_ig}")
for k in keys_ig:
    if 'dont_have' in k or 'already_have' in k:
        print(f'  Found key: {k}')

# Check ha section (lines 1042-1374, 0-indexed 1041-1373)
ha_text = ''.join(lines[1041:1373])
keys_ha = re.findall(r"'(\w+)':\s*'", ha_text)
print(f'\nha section: {len(keys_ha)} keys')
print(f"  'dont_have_account_register' in ha: {'dont_have_account_register' in keys_ha}")
for k in keys_ha:
    if 'dont_have' in k or 'already_have' in k:
        print(f'  Found key: {k}')

# Check yo section (lines 375-708, 0-indexed 374-707)
yo_text = ''.join(lines[374:707])
keys_yo = re.findall(r"'(\w+)':\s*'", yo_text)
print(f'\nyo section: {len(keys_yo)} keys')
print(f"  'dont_have_account_register' in yo: {'dont_have_account_register' in keys_yo}")
for k in keys_yo:
    if 'dont_have' in k or 'already_have' in k:
        print(f'  Found key: {k}')
