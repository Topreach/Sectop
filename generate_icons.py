#!/usr/bin/env python3
"""
Generate Android app icons from sectoplogo.png for all mipmap densities.
"""

import os
import sys

# Try to install Pillow if not available
try:
    from PIL import Image
except ImportError:
    print("Pillow not found. Attempting to install...")
    ret = os.system(f'"{sys.executable}" -m pip install Pillow')
    if ret != 0:
        print("Failed to install Pillow. Please install it manually: pip install Pillow")
        sys.exit(1)
    from PIL import Image

# Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
LOGO_PATH = os.path.join(BASE_DIR, "sectoplogo.png")
RES_DIR = os.path.join(BASE_DIR, "frontend", "android", "app", "src", "main", "res")

# Mipmap densities and their target sizes
DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ADAPTIVE_ICON_XML = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/launch_background"/>
    <foreground android:drawable="@mipmap/ic_launcher"/>
</adaptive-icon>
'''


def main():
    if not os.path.exists(LOGO_PATH):
        print(f"ERROR: Logo file not found at {LOGO_PATH}")
        sys.exit(1)

    print(f"Opening logo: {LOGO_PATH}")
    logo = Image.open(LOGO_PATH)
    print(f"Logo size: {logo.size}, mode: {logo.mode}")

    # Generate PNG icons for each density
    for density_dir, size in DENSITIES.items():
        target_dir = os.path.join(RES_DIR, density_dir)
        os.makedirs(target_dir, exist_ok=True)

        target_path = os.path.join(target_dir, "ic_launcher.png")

        # Remove old XML file if it exists in hdpi
        old_xml = os.path.join(target_dir, "ic_launcher.xml")
        if os.path.exists(old_xml):
            print(f"  Removing old XML: {old_xml}")
            os.remove(old_xml)

        # Resize and save
        resized = logo.resize((size, size), Image.LANCZOS)
        resized.save(target_path, "PNG")
        print(f"  Created: {target_path} ({size}x{size})")

    # Create adaptive icon XML files in mipmap-anydpi-v26
    anydpi_dir = os.path.join(RES_DIR, "mipmap-anydpi-v26")
    os.makedirs(anydpi_dir, exist_ok=True)

    # ic_launcher.xml
    launcher_xml_path = os.path.join(anydpi_dir, "ic_launcher.xml")
    with open(launcher_xml_path, "w", encoding="utf-8") as f:
        f.write(ADAPTIVE_ICON_XML)
    print(f"  Created: {launcher_xml_path}")

    # ic_launcher_round.xml
    launcher_round_xml_path = os.path.join(anydpi_dir, "ic_launcher_round.xml")
    with open(launcher_round_xml_path, "w", encoding="utf-8") as f:
        f.write(ADAPTIVE_ICON_XML)
    print(f"  Created: {launcher_round_xml_path}")

    print("\nAll icons generated successfully!")


if __name__ == "__main__":
    main()
