# Fix flutter_local_notifications Compilation Error

## Problem
The build fails with a Java compilation error in `flutter_local_notifications-16.3.3`:
```
error: reference to bigLargeIcon is ambiguous
  bigPictureStyle.bigLargeIcon(null);
  both method bigLargeIcon(Bitmap) in BigPictureStyle and method bigLargeIcon(Icon) in BigPictureStyle match
```

This happens because newer Android SDK versions added `bigLargeIcon(Icon)` alongside the existing `bigLargeIcon(Bitmap)`, and passing `null` is ambiguous.

## Solution
Patch the plugin's Java source file in the pub cache to cast `null` to `Bitmap`, resolving the ambiguity.

## Tasks

### Task 1: Patch flutter_local_notifications plugin
- **File**: The plugin's Java source in pub cache
  - Path: `/root/.pub-cache/hosted/pub.dev/flutter_local_notifications-16.3.3/android/src/main/java/com/dexterous/flutterlocalnotifications/FlutterLocalNotificationsPlugin.java`
- **Change**: On line 1033, change `bigPictureStyle.bigLargeIcon(null);` to `bigPictureStyle.bigLargeIcon((Bitmap) null);`
- **Note**: This file is in the pub cache, not in the project source. The build script's `patch_plugins()` function should handle this.
- **Status**: ✅ Completed - Patch added to build script

### Task 2: Add the patch to build script
- **File**: `deploy/scripts/build-android-apk.sh`
- **Change**: In the `patch_plugins()` function, add a new section after the jcenter() replacement that patches the `flutter_local_notifications` plugin's ambiguous `bigLargeIcon(null)` call.
- **Add after line 230** (after `jcenter() replacement complete`):
- **Status**: ✅ Completed - Patch added at lines 232-247
```bash
  # Fix flutter_local_notifications ambiguous bigLargeIcon(null) call
  # Newer Android SDKs added bigLargeIcon(Icon) alongside bigLargeIcon(Bitmap),
  # making a null argument ambiguous. Cast to Bitmap to resolve.
  log_info "Patching flutter_local_notifications ambiguous bigLargeIcon call..."
  local FLN_FILE="$PUB_CACHE_DIR/hosted/pub.dev/flutter_local_notifications-16.3.3/android/src/main/java/com/dexterous/flutterlocalnotifications/FlutterLocalNotificationsPlugin.java"
  if [ -f "$FLN_FILE" ]; then
    if grep -q "bigPictureStyle.bigLargeIcon(null)" "$FLN_FILE" 2>/dev/null; then
      sed -i 's/bigPictureStyle\.bigLargeIcon(null)/bigPictureStyle.bigLargeIcon((Bitmap) null)/' "$FLN_FILE"
      log_info "  Patched bigLargeIcon(null) -> bigLargeIcon((Bitmap) null)"
    else
      log_info "  bigLargeIcon(null) not found (may already be patched)"
    fi
  else
    log_warn "  flutter_local_notifications plugin file not found at $FLN_FILE"
  fi
```
