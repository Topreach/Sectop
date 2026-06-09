#!/usr/bin/env python3
"""
Patch workmanager plugin v1 Android embedding → v2 embedding.

Reads WorkmanagerPlugin.kt and BackgroundWorker.kt from the given plugin
directory, applies targeted string replacements, and writes the results.

Usage:
    python3 patch-workmanager-v2-embedding.py <workmanager-plugin-dir>
"""

import re
import sys
import os


def _remove_balanced_block(text: str, start_marker: str) -> str:
    """Remove a brace-delimited block starting with *start_marker*.

    Finds the first occurrence of *start_marker*, then counts brace depth
    from that point forward, removing everything up to and including the
    matching closing brace.
    """
    idx = text.find(start_marker)
    if idx == -1:
        return text

    # Start scanning after the marker
    pos = idx + len(start_marker)
    depth = 1  # we already consumed the opening brace inside start_marker
    while pos < len(text) and depth > 0:
        ch = text[pos]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        pos += 1

    # Remove from idx to pos (inclusive of the closing brace)
    return text[:idx] + text[pos:]


def patch_workmanager_plugin(filepath: str) -> bool:
    """Rewrite WorkmanagerPlugin.kt from v1 (Registrar) to v2 (FlutterPlugin)."""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    original = content

    # 1. Replace imports: remove PluginRegistry.Registrar, add FlutterPlugin
    content = content.replace(
        "import io.flutter.plugin.common.PluginRegistry.Registrar",
        "import io.flutter.embedding.engine.plugins.FlutterPlugin",
    )

    # 2. Change class declaration
    #    From: class WorkmanagerPlugin() : MethodCallHandler {
    #    To:   class WorkmanagerPlugin : FlutterPlugin, MethodCallHandler {
    content = re.sub(
        r"class\s+WorkmanagerPlugin\s*\(\s*\)\s*:\s*MethodCallHandler\s*\{",
        "class WorkmanagerPlugin : FlutterPlugin, MethodCallHandler {",
        content,
    )

    # 3. Remove the entire companion object block (registerWith + channel var)
    #    Use brace-counting to handle nested braces inside registerWith function.
    content = _remove_balanced_block(content, "companion object {")

    # 4. Add onAttachedToEngine and onDetachedFromEngine methods
    #    Insert them right after the opening class brace, before onMethodCall.
    v2_methods = """
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "be.tramckrijte.workmanager")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

"""

    # Insert after the class declaration line
    content = content.replace(
        "class WorkmanagerPlugin : FlutterPlugin, MethodCallHandler {",
        "class WorkmanagerPlugin : FlutterPlugin, MethodCallHandler {"
        + v2_methods,
    )

    # 5. Clean up double blank lines
    content = re.sub(r"\n{3,}", "\n\n", content)

    if content == original:
        print("  No changes needed for WorkmanagerPlugin.kt")
        return False

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)
    print("  Patched WorkmanagerPlugin.kt")
    return True


def patch_background_worker(filepath: str) -> bool:
    """Rewrite BackgroundWorker.kt from v1 ShimPluginRegistry to v2 direct attachment.

    Uses a generic approach: finds and replaces ALL v1 embedding patterns
    (shim, ShimPluginRegistry, pluginRegistryCallback, registerWith, Registrar)
    regardless of the specific variable names or structure used.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    original = content
    any_change = False

    # --- Debug: print first 120 lines to see actual file structure ---
    lines = content.split("\n")
    print(f"  [DEBUG] BackgroundWorker.kt has {len(lines)} lines")
    print(f"  [DEBUG] First {min(120, len(lines))} lines:")
    for i, line in enumerate(lines[:120], 1):
        print(f"  [DEBUG] {i:4d}: {line}")

    # --- 1. Replace v1 imports with v2 equivalents ---

    # Replace import io.flutter.app.FlutterActivity -> import io.flutter.embedding.engine.FlutterEngine
    new_content = content.replace(
        "import io.flutter.app.FlutterActivity",
        "import io.flutter.embedding.engine.FlutterEngine",
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced import io.flutter.app.FlutterActivity")

    # Replace import io.flutter.plugin.common.PluginRegistry -> import io.flutter.embedding.engine.dart.DartExecutor
    new_content = content.replace(
        "import io.flutter.plugin.common.PluginRegistry",
        "import io.flutter.embedding.engine.dart.DartExecutor",
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced import io.flutter.plugin.common.PluginRegistry")

    # Remove import io.flutter.plugin.common.ShimPluginRegistry entirely
    new_content = content.replace("import io.flutter.plugin.common.ShimPluginRegistry", "")
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Removed import io.flutter.plugin.common.ShimPluginRegistry")

    # --- 2. Generic v1 pattern replacements ---

    # 2a. Replace any line containing ShimPluginRegistry(...) construction
    #     Pattern: val <name> = ShimPluginRegistry(<param>)
    #     or:      val <name> = ShimPluginRegistry ( <param> )
    new_content = re.sub(
        r"val\s+\w+\s*=\s*ShimPluginRegistry\s*\([^)]*\)",
        "// v2: ShimPluginRegistry no longer needed",
        content,
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced ShimPluginRegistry construction")

    # 2b. Replace any line containing .registrarFor(...)
    #     Pattern: val <name> = <something>.registrarFor(<param>)
    new_content = re.sub(
        r"val\s+\w+\s*=\s*\w+\.registrarFor\s*\([^)]*\)",
        "// v2: register directly without registrar",
        content,
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced registrarFor call")

    # 2c. Replace any line containing BackgroundWorker.registerWith(...)
    #     Pattern: BackgroundWorker.registerWith(<param>)
    #     or:      <something>.registerWith(<param>)
    new_content = re.sub(
        r"BackgroundWorker\.registerWith\s*\([^)]*\)",
        "WorkmanagerPlugin().onAttachedToEngine(flutterEngine.dartExecutor.binaryMessenger)",
        content,
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced BackgroundWorker.registerWith")

    # 2d. Replace any line containing pluginRegistryCallback
    #     This is a v1 pattern where a callback provides a PluginRegistry
    new_content = re.sub(
        r".*pluginRegistryCallback.*",
        "        // v2: pluginRegistryCallback replaced with direct engine access",
        content,
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced pluginRegistryCallback line")

    # 2e. Replace any remaining reference to ShimPluginRegistry (not as import)
    new_content = re.sub(
        r"\bShimPluginRegistry\b",
        "/* ShimPluginRegistry */",
        content,
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced remaining ShimPluginRegistry references")

    # 2f. Replace any remaining reference to .registrarFor(...)
    new_content = re.sub(
        r"\w+\.registrarFor\s*\([^)]*\)",
        "/* registrarFor removed */",
        content,
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced remaining registrarFor calls")

    # 2g. Replace any line containing registerWith (generic)
    new_content = re.sub(
        r"\w+\.registerWith\s*\([^)]*\)",
        "WorkmanagerPlugin().onAttachedToEngine(flutterEngine.dartExecutor.binaryMessenger)",
        content,
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced remaining registerWith calls")

    # 2h. Replace any val key = "BackgroundWorker" or val key2 = "WorkmanagerPlugin"
    new_content = re.sub(
        r'val\s+\w+\s*=\s*"(BackgroundWorker|WorkmanagerPlugin)"',
        "// v2 embedding",
        content,
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  [DEBUG] Replaced key variable declarations")

    # --- 3. Debug: check for remaining v1 patterns ---
    v1_patterns = ["shim", "ShimPluginRegistry", "pluginRegistryCallback",
                    "registerWith", "Registrar"]
    remaining_lines = []
    for i, line in enumerate(content.split("\n"), 1):
        stripped = line.strip()
        if stripped and not stripped.startswith("//") and not stripped.startswith("/*"):
            for pattern in v1_patterns:
                if pattern in line:
                    remaining_lines.append((i, line.strip(), pattern))
                    break

    if remaining_lines:
        print(f"  [WARNING] {len(remaining_lines)} line(s) still contain v1 patterns:")
        for line_no, line_text, pattern in remaining_lines:
            print(f"  [WARNING]   Line {line_no}: ...{pattern}... -> {line_text}")
    else:
        print("  [DEBUG] No remaining v1 patterns detected")

    # --- 4. Clean up double blank lines ---
    new_content = re.sub(r"\n{3,}", "\n\n", content)
    if new_content != content:
        any_change = True
        content = new_content

    if not any_change:
        print("  No changes needed for BackgroundWorker.kt")
        return False

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)
    print("  Patched BackgroundWorker.kt")
    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: patch-workmanager-v2-embedding.py <workmanager-plugin-dir>")
        sys.exit(1)

    plugin_dir = sys.argv[1]
    if not os.path.isdir(plugin_dir):
        print(f"Error: directory not found: {plugin_dir}")
        sys.exit(1)

    wp_file = os.path.join(plugin_dir, "WorkmanagerPlugin.kt")
    bw_file = os.path.join(plugin_dir, "BackgroundWorker.kt")

    any_change = False

    if os.path.isfile(wp_file):
        any_change |= patch_workmanager_plugin(wp_file)
    else:
        print(f"  WorkmanagerPlugin.kt not found at {wp_file}")

    if os.path.isfile(bw_file):
        any_change |= patch_background_worker(bw_file)
    else:
        print(f"  BackgroundWorker.kt not found at {bw_file}")

    if not any_change:
        print("  No files were modified (already patched or not found)")
        sys.exit(0)


if __name__ == "__main__":
    main()
