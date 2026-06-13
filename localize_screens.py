#!/usr/bin/env python3
"""
Automated script to convert hardcoded strings in screen files to use context.tr('key').
"""
import os, re

D = os.path.dirname(__file__)

# Build string-to-key mapping from localization.dart
LOC_FILE = os.path.join(D, 'frontend/lib/core/localization.dart')
with open(LOC_FILE, 'r', encoding='utf-8') as f:
    loc_content = f.read()

# Extract all key-value pairs from the en section
en_start = loc_content.find("'en': {")
en_end = loc_content.find("},", en_start)
en_section = loc_content[en_start:en_end]

# Build mapping: English string -> localization key
# Also build reverse mapping for common patterns
string_to_key = {}
for m in re.finditer(r"'([^']+)':\s'([^']*)'", en_section):
    key = m.group(1)
    value = m.group(2)
    if value:
        string_to_key[value] = key

# Also add some common variations
string_to_key['SEND SOS'] = 'send_sos'
string_to_key['Quick Actions'] = 'quick_actions'
string_to_key['Safe Zones'] = 'safe_zones'
string_to_key['Mesh Network'] = 'mesh_network'
string_to_key['Messages'] = 'messages'
string_to_key['First Aid'] = 'first_aid'
string_to_key['System Status'] = 'system_status'
string_to_key['Cloud Connection'] = 'cloud_connection'
string_to_key['Emergency Tools'] = 'emergency_tools'
string_to_key['Broadcasts'] = 'broadcasts'
string_to_key['Radio'] = 'radio'
string_to_key['Walkie-Talkie'] = 'walkie_talkie'
string_to_key['Danger Zones'] = 'danger_zones'
string_to_key['Data Sync'] = 'data_sync'
string_to_key['Connected'] = 'connected'
string_to_key['Offline'] = 'offline'

# Sort by length (longest first) to avoid partial replacements
sorted_strings = sorted(string_to_key.keys(), key=len, reverse=True)

# Files to process
screen_files = [
    'frontend/lib/modules/auth/screens/login_screen.dart',
    'frontend/lib/modules/auth/screens/splash_screen.dart',
    'frontend/lib/modules/auth/screens/permission_screen.dart',
    'frontend/lib/modules/auth/screens/forgot_password_screen.dart',
    'frontend/lib/modules/auth/screens/reset_password_screen.dart',
    'frontend/lib/modules/auth/screens/delete_account_screen.dart',
    'frontend/lib/modules/sos/screens/sos_screen.dart',
    'frontend/lib/modules/sos/screens/dashboard_screen.dart',
    'frontend/lib/modules/sos/screens/broadcast_screen.dart',
    'frontend/lib/modules/sos/screens/create_broadcast_screen.dart',
    'frontend/lib/modules/sos/screens/radio_broadcast_screen.dart',
    'frontend/lib/modules/sos/screens/tip_off_screen.dart',
    'frontend/lib/modules/sos/screens/tip_review_screen.dart',
    'frontend/lib/modules/sos/screens/incident_report_screen.dart',
    'frontend/lib/modules/sos/screens/inbox_screen.dart',
    'frontend/lib/modules/sos/screens/message_detail_screen.dart',
    'frontend/lib/modules/sos/screens/mesh_status_screen.dart',
    'frontend/lib/modules/sos/screens/safe_route_screen.dart',
    'frontend/lib/modules/sos/screens/profile_screen.dart',
    'frontend/lib/modules/sos/screens/walkie_talkie_monitor_screen.dart',
    'frontend/lib/modules/sos/screens/zone_details_screen.dart',
    'frontend/lib/modules/sos/screens/offline_resources_screen.dart',
    'frontend/lib/modules/sos/screens/help_screen.dart',
    'frontend/lib/modules/sos/screens/how_to_use_screen.dart',
    'frontend/lib/modules/sos/screens/privacy_policy_screen.dart',
    'frontend/lib/modules/sos/screens/emergency_contacts_screen.dart',
    'frontend/lib/modules/sos/screens/first_aid_screen.dart',
    'frontend/lib/modules/maps/screens/map_screen.dart',
    'frontend/lib/modules/ai/widgets/threat_awareness_card.dart',
    'frontend/lib/modules/sos/widgets/terrorist_location_card.dart',
]

# Import line to add
LOCALIZATION_IMPORT = "import '../../../core/localization.dart';"

def get_relative_import(filepath):
    """Calculate the correct relative import path for localization.dart."""
    depth = filepath.replace('\\', '/').count('/') - 1  # frontend/lib/ is 2 levels
    # Count how many levels deep from frontend/lib/
    parts = filepath.replace('\\', '/').split('/')
    lib_idx = parts.index('lib')
    depth_from_lib = len(parts) - lib_idx - 1  # -1 for the filename
    ups = '../' * (depth_from_lib - 1)  # go up to lib/
    return f"import '{ups}core/localization.dart';"

def needs_import(content, import_line):
    """Check if file already has the import."""
    return import_line not in content

def replace_strings_in_file(filepath):
    """Replace hardcoded strings with context.tr('key') in a file."""
    fullpath = os.path.join(D, filepath)
    if not os.path.exists(fullpath):
        print(f"  SKIP: {filepath} not found")
        return False
    
    with open(fullpath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    
    # Add import if needed
    import_line = get_relative_import(filepath)
    if needs_import(content, import_line):
        # Find the last import line
        import_end = 0
        for m in re.finditer(r"^import .*;$", content, re.MULTILINE):
            import_end = m.end()
        if import_end > 0:
            # Insert after last import
            content = content[:import_end] + '\n' + import_line + content[import_end:]
        else:
            # No imports? Add after package declaration
            content = import_line + '\n' + content
    
    # Replace hardcoded strings that appear as Text() children, labels, titles, etc.
    # We need to be careful to only replace string literals, not variables or keys
    
    # Strategy: Replace specific patterns
    # Pattern 1: Text('Hardcoded String') -> Text(context.tr('key'))
    # Pattern 2: label: 'Hardcoded String' -> label: context.tr('key')
    # Pattern 3: title: 'Hardcoded String' -> title: context.tr('key')
    # Pattern 4: subtitle: 'Hardcoded String' -> subtitle: context.tr('key')
    # Pattern 5: 'Hardcoded String' in other contexts
    
    # Process each known string, longest first
    for s in sorted_strings:
        key = string_to_key[s]
        if not key:
            continue
        
        # Escape special regex characters in the string
        escaped = re.escape(s)
        
        # Replace in Text('string') context
        content = re.sub(
            r"Text\('" + escaped + r"'\)",
            "Text(context.tr('" + key + "'))",
            content
        )
        # Replace in Text("string") context (double quotes)
        content = re.sub(
            r'Text\("' + escaped + r'"\)',
            'Text(context.tr(\'' + key + '\'))',
            content
        )
        
        # Replace in const Text('string') context
        content = re.sub(
            r"const Text\('" + escaped + r"'\)",
            "Text(context.tr('" + key + "'))",
            content
        )
        content = re.sub(
            r'const Text\("' + escaped + r'"\)',
            'Text(context.tr(\'' + key + '\'))',
            content
        )
        
        # Replace label: 'string'
        content = re.sub(
            r"label:\s*'" + escaped + r"'",
            "label: context.tr('" + key + "')",
            content
        )
        content = re.sub(
            r'label:\s*"' + escaped + r'"',
            "label: context.tr('" + key + "')",
            content
        )
        
        # Replace title: 'string' (but not in Text() which is already handled)
        content = re.sub(
            r"(?<!Text\()title:\s*'" + escaped + r"'",
            "title: context.tr('" + key + "')",
            content
        )
        content = re.sub(
            r'(?<!Text\()title:\s*"' + escaped + r'"',
            "title: context.tr('" + key + "')",
            content
        )
        
        # Replace subtitle: 'string'
        content = re.sub(
            r"subtitle:\s*'" + escaped + r"'",
            "subtitle: context.tr('" + key + "')",
            content
        )
        content = re.sub(
            r'subtitle:\s*"' + escaped + r'"',
            "subtitle: context.tr('" + key + "')",
            content
        )
        
        # Replace hintText: 'string'
        content = re.sub(
            r"hintText:\s*'" + escaped + r"'",
            "hintText: context.tr('" + key + "')",
            content
        )
        
        # Replace helperText: 'string'
        content = re.sub(
            r"helperText:\s*'" + escaped + r"'",
            "helperText: context.tr('" + key + "')",
            content
        )
        
        # Replace snackBar Text('string')
        content = re.sub(
            r"SnackBar\(content:\s*Text\('" + escaped + r"'\)\)",
            "SnackBar(content: Text(context.tr('" + key + "')))",
            content
        )
    
    if content != original:
        with open(fullpath, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    return False

# Process all files
changed = 0
for f in screen_files:
    if replace_strings_in_file(f):
        print(f"  MODIFIED: {f}")
        changed += 1
    else:
        print(f"  UNCHANGED: {f}")

print(f"\nTotal files modified: {changed}")
