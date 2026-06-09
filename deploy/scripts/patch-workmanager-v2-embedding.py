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

    Uses exact string replacements first, then falls back to regex-based
    replacements for robustness against minor formatting differences.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    original = content

    # --- 1. Replace imports (exact match) ---
    content = content.replace(
        "import io.flutter.app.FlutterActivity",
        "import io.flutter.embedding.engine.FlutterEngine",
    )
    content = content.replace(
        "import io.flutter.plugin.common.PluginRegistry",
        "import io.flutter.embedding.engine.dart.DartExecutor",
    )

    # --- 2. Replace v1 registration block (exact match) ---
    content = content.replace(
        "val shim = ShimPluginRegistry(flutterEngine)",
        "val messenger = flutterEngine.dartExecutor.binaryMessenger",
    )
    content = content.replace(
        'val key = "BackgroundWorker"',
        "// v2 embedding",
    )
    content = content.replace(
        'val key2 = "WorkmanagerPlugin"',
        "// v2 embedding",
    )
    content = content.replace(
        "val reg = shim.registrarFor(key)",
        "// v2: register directly",
    )
    content = content.replace(
        "BackgroundWorker.registerWith(reg)",
        "WorkmanagerPlugin().onAttachedToEngine(messenger)",
    )

    # --- 3. Regex fallback: catch v1 patterns that exact replacements missed ---

    # 3a. Replace v1 ShimPluginRegistry import if present
    content = re.sub(
        r"import\s+io\.flutter\.app\.FlutterActivity",
        "import io.flutter.embedding.engine.FlutterEngine",
        content,
    )
    content = re.sub(
        r"import\s+io\.flutter\.plugin\.common\.PluginRegistry",
        "import io.flutter.embedding.engine.dart.DartExecutor",
        content,
    )

    # 3b. Replace ShimPluginRegistry usage
    content = re.sub(
        r"val\s+shim\s*=\s*ShimPluginRegistry\s*\(\s*flutterEngine\s*\)",
        "val messenger = flutterEngine.dartExecutor.binaryMessenger",
        content,
    )

    # 3c. Replace key variable declarations
    content = re.sub(
        r'val\s+key\s*=\s*"BackgroundWorker"',
        '// v2 embedding',
        content,
    )
    content = re.sub(
        r'val\s+key2\s*=\s*"WorkmanagerPlugin"',
        '// v2 embedding',
        content,
    )

    # 3d. Replace registrarFor call
    content = re.sub(
        r"val\s+reg\s*=\s*shim\.registrarFor\s*\(\s*key\s*\)",
        "// v2: register directly",
        content,
    )

    # 3e. Replace registerWith call
    content = re.sub(
        r"BackgroundWorker\.registerWith\s*\(\s*reg\s*\)",
        "WorkmanagerPlugin().onAttachedToEngine(messenger)",
        content,
    )

    if content == original:
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
