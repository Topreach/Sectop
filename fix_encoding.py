#!/usr/bin/env python3
"""Fix double-encoded Unicode in localization.dart.

The file was saved with wrong encoding: UTF-8 bytes of Yoruba/Igbo/Hausa
characters were interpreted as Latin-1 (ISO-8859-1), producing mojibake
like 'Ã¡' instead of 'á', 'á»' instead of 'ọ', etc.

This script reads the file as Latin-1 bytes, re-encodes to UTF-8,
then decodes properly.
"""
import sys

def fix_file(filepath):
    with open(filepath, 'rb') as f:
        raw = f.read()
    
    # Try to detect if the file is double-encoded
    # The pattern: valid UTF-8 bytes that when interpreted as Latin-1
    # produce sequences like Ã¡ (C3 A1) which is actually á in UTF-8
    
    # Strategy: decode as Latin-1, then re-encode as raw bytes, then decode as UTF-8
    # This reverses the double-encoding
    
    try:
        # First, try to decode as UTF-8 to see if it's valid
        text_utf8 = raw.decode('utf-8')
        print("File is valid UTF-8. Checking for mojibake patterns...")
        
        # Check for common mojibake patterns
        mojibake_patterns = ['Ã¡', 'Ã©', 'Ã­', 'Ã³', 'Ãº', 'Ã±',
                            'á»', 'áº¹', 'á¹£', 'á»',
                            'Ä™', 'Å‚', 'Ä‡',
                            'Ã€', 'Ãˆ', 'ÃŒ', 'Ã’', 'Ã™']
        
        found = False
        for pattern in mojibake_patterns:
            if pattern in text_utf8:
                print(f"  Found mojibake pattern: {pattern!r}")
                found = True
        
        if not found:
            print("No mojibake patterns found. File may already be correct.")
            return False
        
        # The fix: decode as Latin-1 to get the raw bytes back, then decode as UTF-8
        text_latin1 = raw.decode('latin-1')
        # Re-encode as Latin-1 to get the original bytes, then decode as UTF-8
        fixed_bytes = text_latin1.encode('latin-1')
        fixed_text = fixed_bytes.decode('utf-8')
        
        # Verify the fix worked
        for pattern in mojibake_patterns:
            if pattern in fixed_text:
                print(f"  WARNING: Still has mojibake: {pattern!r}")
        
        # Write the fixed file
        with open(filepath, 'wb') as f:
            f.write(fixed_text.encode('utf-8'))
        
        print(f"File fixed successfully. {len(raw)} bytes -> {len(fixed_bytes)} bytes")
        return True
        
    except UnicodeDecodeError as e:
        print(f"File is NOT valid UTF-8: {e}")
        print("This is a different kind of corruption.")
        return False

if __name__ == '__main__':
    fix_file('frontend/lib/core/localization.dart')
