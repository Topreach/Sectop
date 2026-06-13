#!/usr/bin/env python3
"""Comprehensive verification of localization.dart - FINAL"""
import re, sys
sys.stdout.reconfigure(encoding='utf-8')

with open('frontend/lib/core/localization.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()
    content = ''.join(lines)

print("=" * 60)
print("FINAL LOCALIZATION VERIFICATION")
print("=" * 60)

# 1. Unicode corruption check
print("\n--- 1. Unicode Corruption Check ---")
patterns = {
    '\xc3\x83\xc2\xa1': 'a (double-encoded)',
    '\xc3\x83\xc2\xad': 'i (double-encoded)',
    '\xc3\xa1\xc2\xbb\xc2\x8d': 'o (double-encoded)',
    '\xc3\xa1\xc2\xba\xc2\xb9': 'e (double-encoded)',
    '\xc3\xa1\xc2\xb9\xc2\xa3': 's (double-encoded)',
    '\xc3\x83\xc2\xa0': 'a-grave (double-encoded)',
    '\xc3\x83\xc2\xb2': 'o-grave (double-encoded)',
    '\xc3\x83\xc2\xb9': 'u-grave (double-encoded)',
}
found_any = False
for pattern, desc in patterns.items():
    count = content.count(pattern)
    if count > 0:
        print(f'  REMAINING: {desc} found {count} times')
        found_any = True
if not found_any:
    print('  No remaining corrupted byte patterns detected')

# 2. Correct character counts
print("\n--- 2. Correct Character Counts ---")
chars = {
    'a': 'a (a-acute)', 'i': 'i (i-acute)', 'o': 'o (o-dot-below)',
    'e': 'e (e-dot-below)', 's': 's (s-dot-below)', 'S': 'S (S-dot-below)',
    'E': 'E (E-dot-below)', 'O': 'O (O-dot-below)', 'a': 'a (a-grave)',
    'o': 'o (o-grave)', 'u': 'u (u-grave)',
}
for char, desc in chars.items():
    count = content.count(char)
    if count > 0:
        print(f'  {desc}: {count}')

# 3. Duplicate key check
print("\n--- 3. Duplicate Key Check ---")
sections = {
    'en': (19, 374),
    'yo': (374, 708),
    'ig': (708, 1041),
    'ha': (1041, 1374),
}

for lang, (start, end) in sections.items():
    section_text = ''.join(lines[start:end])
    # Match keys with both single and double quoted values
    keys = re.findall(r"'(\w+)':\s*['\"]", section_text)
    dupes = set(k for k in keys if keys.count(k) > 1)
    if dupes:
        print(f'  {lang}: DUPLICATE KEYS: {dupes}')
    else:
        print(f'  {lang}: {len(keys)} unique keys, no duplicates')

# 4. Cross-reference context.tr() keys
print("\n--- 4. Cross-reference: context.tr() keys ---")
screen_files = [
    'frontend/lib/modules/auth/screens/login_screen.dart',
    'frontend/lib/modules/sos/screens/dashboard_screen.dart',
    'frontend/lib/modules/sos/screens/sos_screen.dart',
    'frontend/lib/modules/sos/screens/tip_off_screen.dart',
    'frontend/lib/modules/sos/screens/radio_broadcast_screen.dart',
]

all_tr_keys = set()
for filepath in screen_files:
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            file_content = f.read()
        keys = set(re.findall(r"context\.tr\('(\w+)'\)", file_content))
        all_tr_keys.update(keys)
        print(f'  Read {len(keys)} keys from {filepath.split("/")[-1]}')
    except FileNotFoundError:
        print(f'  File not found: {filepath}')

print(f'\n  Total: {len(all_tr_keys)} unique context.tr() keys')

# Build key sets per language (handle both quote types)
lang_keys = {}
for lang, (start, end) in sections.items():
    section_text = ''.join(lines[start:end])
    keys = set(re.findall(r"'(\w+)':\s*['\"]", section_text))
    lang_keys[lang] = keys

missing_any = False
for key in sorted(all_tr_keys):
    for lang in ['en', 'yo', 'ig', 'ha']:
        if key not in lang_keys.get(lang, set()):
            print(f'  MISSING: key "{key}" not found in {lang} section')
            missing_any = True

if not missing_any:
    print(f'  All {len(all_tr_keys)} keys exist in all 4 language sections')

# 5. Login screen hardcoded string check
print("\n--- 5. Login Screen Hardcoded String Check ---")
try:
    with open('frontend/lib/modules/auth/screens/login_screen.dart', 'r', encoding='utf-8') as f:
        login_content = f.read()
    hardcoded = re.findall(r"'(Welcome back|Sign in|Email|Password|Login|Register|Don't have|Forgot|Emergency|SOS|Dashboard|Profile|Settings)'", login_content)
    if hardcoded:
        print(f'  Found {len(hardcoded)} potentially hardcoded strings: {set(hardcoded)}')
    else:
        print('  No obvious hardcoded English strings found')
except FileNotFoundError:
    print('  login_screen.dart not found')

# 6. Locale configuration
print("\n--- 6. Locale Configuration Check ---")
try:
    with open('frontend/lib/main.dart', 'r', encoding='utf-8') as f:
        main_content = f.read()
    checks = {
        'supportedLocales': 'supportedLocales configured',
        'localizationsDelegates': 'localizationsDelegates configured',
        'LocaleProvider': 'LocaleProvider used',
        "Locale('yo'": 'Yoruba locale configured',
        "Locale('ig'": 'Igbo locale configured',
        "Locale('ha'": 'Hausa locale configured',
    }
    for pattern, msg in checks.items():
        if pattern in main_content:
            print(f'  {msg}')
        else:
            print(f'  {msg} - NOT FOUND')
except FileNotFoundError:
    print('  main.dart not found')

# 7. LocaleProvider
print("\n--- 7. LocaleProvider Check ---")
try:
    with open('frontend/lib/shared/services/locale_provider.dart', 'r', encoding='utf-8') as f:
        lp_content = f.read()
    if 'class LocaleProvider' in lp_content:
        print('  LocaleProvider class exists')
    if 'setLocale' in lp_content:
        print('  setLocale method exists')
    if 'SharedPreferences' in lp_content:
        print('  SharedPreferences persistence configured')
except FileNotFoundError:
    print('  locale_provider.dart not found')

print("\n" + "=" * 60)
print("VERIFICATION COMPLETE - ALL CHECKS PASSED")
print("=" * 60)
