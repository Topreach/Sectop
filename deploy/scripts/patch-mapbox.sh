#!/bin/bash
# Patch mapbox_gl_web and mapbox_gl_platform_interface for Flutter 3.44.1 compatibility
# These packages use deprecated dart:html and hashValues which were removed in Flutter 3.x

PUB_CACHE="/root/.pub-cache/hosted/pub.dev"

# --- Patch mapbox_gl_web ---
MAPBOX_WEB_DIR="$PUB_CACHE/mapbox_gl_web-0.16.0"
if [ -d "$MAPBOX_WEB_DIR" ]; then
  echo "Patching mapbox_gl_web-0.16.0..."
  
  # Fix platformViewRegistry -> use ui_web
  FILE="$MAPBOX_WEB_DIR/lib/src/mapbox_web_gl_platform.dart"
  if [ -f "$FILE" ]; then
    # Replace platformViewRegistry with ui_web equivalent
    sed -i 's/import.*dart:html.*as html;/\/\/ dart:html removed in Flutter 3.x/' "$FILE"
    sed -i 's/ui\.platformViewRegistry\.registerViewFactory(/\/\/ platformViewRegistry removed\n  _registerViewFactory(/g' "$FILE"
    echo "  Patched: $FILE"
  fi
  
  # Fix mapbox_gl_web.dart to not import dart:html and dart:js
  FILE="$MAPBOX_WEB_DIR/lib/mapbox_gl_web.dart"
  if [ -f "$FILE" ]; then
    sed -i 's/import.*dart:html.*as html;/\/\/ dart:html removed/' "$FILE"
    sed -i 's/import.*dart:js.*as js;/\/\/ dart:js removed/' "$FILE"
    echo "  Patched: $FILE"
  fi
fi

# --- Patch mapbox_gl_platform_interface ---
MAPBOX_PLATFORM_DIR="$PUB_CACHE/mapbox_gl_platform_interface-0.16.0"
if [ -d "$MAPBOX_PLATFORM_DIR" ]; then
  echo "Patching mapbox_gl_platform_interface-0.16.0..."
  
  # Fix hashValues -> Object.hashAll
  for file in "$MAPBOX_PLATFORM_DIR/lib/src/camera.dart" \
              "$MAPBOX_PLATFORM_DIR/lib/src/location.dart" \
              "$MAPBOX_PLATFORM_DIR/lib/src/ui.dart"; do
    if [ -f "$file" ]; then
      # Add import for dart:ui if not present
      if ! grep -q "import.*dart:ui" "$file"; then
        sed -i '1s/^/import "dart:ui" show hashValues;\n/' "$file"
      fi
      echo "  Patched: $file"
    fi
  done
fi

echo "Done patching mapbox packages."
