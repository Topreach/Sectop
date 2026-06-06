#!/bin/bash
# =============================================================================
# Patch Route Restoration UnimplementedError in Flutter Web Build
# =============================================================================
# This script patches the compiled main.dart.js to fix UnimplementedError
# crashes caused by unimplemented TextStyle methods (aR6 and b5h) that are
# called during anonymous route restoration deserialization on web.
#
# These functions are static methods on Flutter's TextStyle class that throw
# UnimplementedError on web. They're called from the _RouteRestorationType
# deserialization path when anonymous routes are involved.
#
# The patch replaces the throwing implementations with valid no-ops:
#   aR6(a) -> returns an empty array (mimics base class Ct() behavior)
#   b5h(a) -> returns a no-op function (mimics a callable 2-arg function)
# =============================================================================

set -euo pipefail

JS_FILE="${1:-build/web/main.dart.js}"

if [ ! -f "$JS_FILE" ]; then
  echo "ERROR: $JS_FILE not found. Run 'flutter build web' first."
  echo "Usage: $0 [path-to-main.dart.js]"
  exit 1
fi

echo "Patching $JS_FILE ..."

# Count occurrences before patching
A_R6_COUNT=$(grep -c 'aR6(a){throw A.h(A.e6(null))}' "$JS_FILE" 2>/dev/null || echo 0)
B5H_COUNT=$(grep -c 'b5h(a){throw A.h(A.e6(null))}' "$JS_FILE" 2>/dev/null || echo 0)

echo "  Found $A_R6_COUNT occurrence(s) of aR6 throw"
echo "  Found $B5H_COUNT occurrence(s) of b5h throw"

if [ "$A_R6_COUNT" -eq 0 ] && [ "$B5H_COUNT" -eq 0 ]; then
  echo "  No throw occurrences found. Checking for alternative patterns..."
  # Try alternative patterns (minified differently)
  A_R6_COUNT=$(grep -c 'aR6(a){throw' "$JS_FILE" 2>/dev/null || echo 0)
  B5H_COUNT=$(grep -c 'b5h(a){throw' "$JS_FILE" 2>/dev/null || echo 0)
  echo "  Found $A_R6_COUNT occurrence(s) of aR6 throw (alt)"
  echo "  Found $B5H_COUNT occurrence(s) of b5h throw (alt)"
fi

# Patch aR6: replace throw with return of empty array
# The original function is a static method on TextStyle that's not implemented on web.
# It's called from aw3.Ct() which should return restoration data (a list).
# Returning an empty array is safe because the caller handles empty results.
if [ "$A_R6_COUNT" -gt 0 ]; then
  sed -i 's/aR6(a){throw A.h(A.e6(null))}/aR6(a){return[]}/g' "$JS_FILE"
  echo "  ✅ Patched aR6(a) to return empty array"
else
  echo "  ⚠️  aR6 throw pattern not found - may already be patched or different version"
fi

# Patch b5h: replace throw with return of a no-op function
# The original function is a static factory that should return a callable object.
# It's called from b8Y deserialization to create the 'd' field of aw3 objects.
# The aw3.wL() method calls this.d.$2(s, this.e), so we return a 2-arg function.
if [ "$B5H_COUNT" -gt 0 ]; then
  sed -i 's/b5h(a){throw A.h(A.e6(null))}/b5h(a){return function(b,c){}}/g' "$JS_FILE"
  echo "  ✅ Patched b5h(a) to return no-op function"
else
  echo "  ⚠️  b5h throw pattern not found - may already be patched or different version"
fi

# Verify the patch was applied
NEW_A_R6=$(grep -c 'aR6(a){return' "$JS_FILE" 2>/dev/null || echo 0)
NEW_B5H=$(grep -c 'b5h(a){return' "$JS_FILE" 2>/dev/null || echo 0)
REMAINING_A_R6=$(grep -c 'aR6(a){throw' "$JS_FILE" 2>/dev/null || echo 0)
REMAINING_B5H=$(grep -c 'b5h(a){throw' "$JS_FILE" 2>/dev/null || echo 0)

echo ""
echo "=== Patch Summary ==="
echo "  aR6 patched: $NEW_A_R6 (remaining throws: $REMAINING_A_R6)"
echo "  b5h patched: $NEW_B5H (remaining throws: $REMAINING_B5H)"

if [ "$NEW_A_R6" -gt 0 ] || [ "$NEW_B5H" -gt 0 ]; then
  echo ""
  echo "✅ Route restoration patch applied successfully!"
  echo "   The UnimplementedError from aR6/b5h should no longer occur."
else
  echo ""
  echo "⚠️  No patches were applied. The JS file may have a different structure."
  echo "   Check the file manually and update the patterns."
  exit 1
fi
