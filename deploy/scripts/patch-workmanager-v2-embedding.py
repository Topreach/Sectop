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

    Based on the actual file content observed from debug output:
    - Line 14: import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry
    - Line 98: WorkmanagerPlugin.pluginRegistryCallback?.registerWith(ShimPluginRegistry(engine!!))

    The file already uses v2 engine classes everywhere else, so only these
    two precise line-based replacements are needed.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    original = content
    any_change = False

    # --- 1. Remove the ShimPluginRegistry import line ---
    # Actual line: import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry
    new_content = content.replace(
        "import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry",
        "",
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  Removed import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry")

    # --- 2. Replace the pluginRegistryCallback line with a v2 comment ---
    # Actual line: WorkmanagerPlugin.pluginRegistryCallback?.registerWith(ShimPluginRegistry(engine!!))
    new_content = content.replace(
        "WorkmanagerPlugin.pluginRegistryCallback?.registerWith(ShimPluginRegistry(engine!!))",
        "// v2: plugins registered via FlutterPlugin interface",
    )
    if new_content != content:
        any_change = True
        content = new_content
        print("  Replaced pluginRegistryCallback line with v2 comment")

    # --- 3. Clean up double blank lines ---
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
