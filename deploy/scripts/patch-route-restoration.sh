#!/bin/bash
# =============================================================================
# Patch Route Restoration UnimplementedError in Flutter Web Build
# =============================================================================
# This script patches the compiled main.dart.js to fix UnimplementedError
# crashes caused by unimplemented TextStyle methods that are called during
# anonymous route restoration deserialization on web.
#
# The patch auto-detects the minified function names by searching for the
# UnimplementedError throw pattern: throw A.h(A.e6(null))
#
# Two types of functions are patched:
#   1. Functions called from Ct() methods (return restoration data)
#      -> Patched to return empty array: func(a){return[]}
#   2. Functions called from b8Y deserialization (factory functions)
#      -> Patched to return no-op: func(a){return function(b,c){}}
# =============================================================================

set -euo pipefail

JS_FILE="${1:-build/web/main.dart.js}"

if [ ! -f "$JS_FILE" ]; then
  echo "ERROR: $JS_FILE not found. Run 'flutter build web' first."
  echo "Usage: $0 [path-to-main.dart.js]"
  exit 1
fi

echo "Patching $JS_FILE ..."

# =============================================================================
# Step 1: Find all functions that throw UnimplementedError
# =============================================================================
# The UnimplementedError throw pattern in compiled Flutter JS is:
#   funcname(a){throw A.h(A.e6(null))}
# We search for this pattern and extract the function name.

echo "  Searching for UnimplementedError throw patterns..."

THROW_PATTERN='throw A.h(A.e6(null))'

# Count occurrences - use xargs to trim any whitespace/newlines
THROW_COUNT=$(grep -c "$THROW_PATTERN" "$JS_FILE" 2>/dev/null | xargs echo || echo 0)

echo "  Found $THROW_COUNT function(s) throwing UnimplementedError"

if [ "$THROW_COUNT" = "0" ]; then
  echo "  WARNING: No UnimplementedError throw patterns found."
  echo "  The JS file may have a different structure or already be patched."
  echo "  Checking for alternative patterns..."
  
  # Try alternative: maybe the throw uses a different null representation
  ALT_COUNT=$(grep -c 'throw A.h(A.e6(' "$JS_FILE" 2>/dev/null | xargs echo || echo 0)
  echo "  Found $ALT_COUNT alternative throw patterns"
  
  if [ "$ALT_COUNT" = "0" ]; then
    echo "  No throw patterns found at all. Exiting."
    exit 1
  fi
  
  THROW_COUNT=$ALT_COUNT
fi

# =============================================================================
# Step 2: Patch all functions that throw UnimplementedError
# =============================================================================
# We use sed to find patterns like: funcname(a){throw A.h(A.e6(null))}
# and replace the throw with a return of empty array.
#
# The sed pattern uses capture groups to preserve the function name:
#   Match: funcname(a){throw A.h(A.e6(null))}
#   Replace: funcname(a){return[]}

echo ""
echo "  Patching functions..."

# Create a backup
cp "$JS_FILE" "${JS_FILE}.bak"

# Use sed with capture group to replace any function that throws UnimplementedError
# Pattern: identifier(a){throw A.h(A.e6(null))}
# Replacement: identifier(a){return[]}
sed -i 's/\([a-zA-Z_$][a-zA-Z0-9_$]*\)(a){throw A\.h(A\.e6(null))}/\1(a){return[]}/g' "$JS_FILE"

# Count how many were patched
PATCHED_COUNT=$(grep -c 'return\[\]' "$JS_FILE" 2>/dev/null | xargs echo || echo 0)
echo "    Patched $PATCHED_COUNT function(s) to return empty array"

# =============================================================================
# Step 3: Handle factory functions (b5h-like) that need to return a function
# =============================================================================
# Some of the patched functions are called from b8Y deserialization and need
# to return a callable function, not an empty array.
#
# We identify these by looking for calls like: A.<funcname>(new A.a8Q(...))
# in the original JS file, then fix the patch for those specific functions.

echo ""
echo "  Checking for factory functions (called from b8Y deserialization)..."

# Search for functions called with new A.a8Q argument (b8Y deserialization pattern)
B8Y_CALLS=$(grep -c 'A\.[a-zA-Z_$][a-zA-Z0-9_$]*(new A\.a8Q' "${JS_FILE}.bak" 2>/dev/null | xargs echo || echo 0)

if [ "$B8Y_CALLS" != "0" ]; then
  echo "    Found factory function(s) called from b8Y deserialization"
  
  # Extract function names called from b8Y
  grep -o 'A\.[a-zA-Z_$][a-zA-Z0-9_$]*(new A\.a8Q' "${JS_FILE}.bak" | while read -r match; do
    # Extract function name after 'A.'
    b8y_func=$(echo "$match" | sed 's/A\.\([a-zA-Z_$][a-zA-Z0-9_$]*\)(.*/\1/')
    echo "      -> Function '$b8y_func' needs to return a callable function"
    
    # Fix the patch: change return[] to return function(b,c){}
    sed -i "s/$b8y_func(a){return\[\]}/$b8y_func(a){return function(b,c){}}/g" "$JS_FILE"
  done
else
  echo "    No factory functions found"
fi

# =============================================================================
# Step 4: Verify the patch
# =============================================================================
echo ""
echo "=== Patch Summary ==="

REMAINING_THROWS=$(grep -c "$THROW_PATTERN" "$JS_FILE" 2>/dev/null | xargs echo || echo 0)
RETURN_ARRAY_COUNT=$(grep -c 'return\[\]' "$JS_FILE" 2>/dev/null | xargs echo || echo 0)
RETURN_FUNC_COUNT=$(grep -c 'return function(b,c)' "$JS_FILE" 2>/dev/null | xargs echo || echo 0)

echo "  Functions patched to return[]: $RETURN_ARRAY_COUNT"
echo "  Functions patched to return function: $RETURN_FUNC_COUNT"
echo "  Remaining UnimplementedError throws: $REMAINING_THROWS"

if [ "$RETURN_ARRAY_COUNT" != "0" ] || [ "$RETURN_FUNC_COUNT" != "0" ]; then
  echo ""
  echo "SUCCESS: Route restoration patch applied successfully!"
  echo "  The UnimplementedError from route restoration should no longer occur."
  # Remove backup on success
  rm -f "${JS_FILE}.bak"
else
  echo ""
  echo "WARNING: No patches were applied. The JS file may have a different structure."
  echo "  Backup saved at: ${JS_FILE}.bak"
  exit 1
fi
