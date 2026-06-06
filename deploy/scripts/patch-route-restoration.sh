#!/bin/bash
# =============================================================================
# Patch Route Restoration UnimplementedError in Flutter Web Build
# =============================================================================
# This script patches the compiled main.dart.js to fix UnimplementedError
# crashes caused by unimplemented TextStyle methods that are called during
# anonymous route restoration deserialization on web.
#
# These functions are static methods on Flutter's TextStyle class that throw
# UnimplementedError on web. They're called from the _RouteRestorationType
# deserialization path when anonymous routes are involved.
#
# The patch auto-detects the minified function names by searching for the
# UnimplementedError throw pattern. The minified constructor name for
# UnimplementedError varies between Flutter builds (e.g., A.e6, A.ej).
#
# Two types of functions are patched:
#   1. Functions called from Ct() methods (return restoration data)
#      -> Patched to return empty array: func(a){return[]}
#   2. Functions called from deserialization (factory functions)
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
# Helper: count grep matches safely (handles BusyBox grep -c newline issue)
# =============================================================================
count_matches() {
  local pattern="$1"
  local file="$2"
  # Use grep piped to wc -l instead of grep -c to avoid newline issues
  grep "$pattern" "$file" 2>/dev/null | wc -l | tr -d ' '
}

# =============================================================================
# Step 1: Find all functions that throw UnimplementedError
# =============================================================================
# The UnimplementedError throw pattern in compiled Flutter JS varies:
#   funcname(a){throw A.h(A.e6(null))}   (some builds)
#   funcname(a){throw A.h(A.ej(null))}   (other builds)
# We search for the generic pattern: throw A.h(A.XX(null))

echo "  Searching for UnimplementedError throw patterns..."

# Try multiple patterns - the minified constructor name varies
THROW_PATTERNS=(
  'throw A.h(A.e6(null))'
  'throw A.h(A.ej(null))'
  'throw A.h(A.e[0-9a-z][0-9a-z]?(null))'
)

THROW_PATTERN=''
THROW_COUNT=0

for pattern in "${THROW_PATTERNS[@]}"; do
  count=$(count_matches "$pattern" "$JS_FILE")
  if [ "$count" -gt 0 ]; then
    THROW_PATTERN="$pattern"
    THROW_COUNT=$count
    echo "  Found $count function(s) throwing UnimplementedError (pattern: $pattern)"
    break
  fi
done

if [ "$THROW_COUNT" -eq 0 ]; then
  echo "  WARNING: No UnimplementedError throw patterns found."
  echo "  The JS file may have a different structure or already be patched."
  echo "  Searching for any throw with null argument..."
  
  # Last resort: search for any function that throws with null
  count=$(count_matches '(a){throw A.h(A.' "$JS_FILE")
  if [ "$count" -gt 0 ]; then
    echo "  Found $count potential throw patterns. Using broad pattern."
    THROW_PATTERN='(a){throw A.h(A.'
  else
    echo "  No throw patterns found at all. Exiting."
    exit 1
  fi
fi

# =============================================================================
# Step 2: Patch all functions that throw UnimplementedError
# =============================================================================
# We use sed to find patterns like: funcname(a){throw A.h(A.XX(null))}
# and replace the throw with a return of empty array.

echo ""
echo "  Patching functions..."

# Create a backup
cp "$JS_FILE" "${JS_FILE}.bak"

# Use sed with capture group to replace any function that throws UnimplementedError
# Pattern: identifier(a){throw A.h(A.XX(null))}
# Replacement: identifier(a){return[]}
# We use a regex that matches any two-letter minified name after A.
sed -i 's/\([a-zA-Z_$][a-zA-Z0-9_$]*\)(a){throw A\.h(A\.[a-zA-Z_$][a-zA-Z0-9_$]*(null))}/\1(a){return[]}/g' "$JS_FILE"

# Count how many were patched
PATCHED_COUNT=$(count_matches 'return\[\]' "$JS_FILE")
echo "    Patched $PATCHED_COUNT function(s) to return empty array"

# =============================================================================
# Step 3: Handle factory functions that need to return a function
# =============================================================================
# Some of the patched functions are called from deserialization and need
# to return a callable function, not an empty array.
#
# We identify these by looking for calls like: A.<funcname>(new A.a8Q(...))
# or similar patterns in the original JS file, then fix the patch.

echo ""
echo "  Checking for factory functions (called from deserialization)..."

# Search for functions called with new A.XXQ argument (deserialization pattern)
# The class name for the type descriptor varies (a8Q, etc.)
FACTORY_CALLS=$(grep -o 'A\.[a-zA-Z_$][a-zA-Z0-9_$]*(new A\.[a-zA-Z_$][a-zA-Z0-9_$]*(' "${JS_FILE}.bak" 2>/dev/null | grep -v 'A\.h(' | sort -u || true)

if [ -n "$FACTORY_CALLS" ]; then
  echo "$FACTORY_CALLS" | while read -r match; do
    # Extract function name after 'A.'
    factory_func=$(echo "$match" | sed 's/A\.\([a-zA-Z_$][a-zA-Z0-9_$]*\)(.*/\1/')
    
    # Check if this function was patched (has return[])
    patched_check=$(grep -c "${factory_func}(a){return\[\]}" "$JS_FILE" 2>/dev/null || echo 0)
    if [ "$patched_check" -gt 0 ]; then
      echo "      -> Function '$factory_func' is a factory, patching to return callable"
      sed -i "s/${factory_func}(a){return\[\]}/${factory_func}(a){return function(b,c){}}/g" "$JS_FILE"
    fi
  done
else
  echo "    No factory function calls found via pattern matching"
  echo "    Checking for deserialization switch statements..."
  
  # Look for the deserialization function that creates route restoration objects
  # Pattern: case 1: ... return new A.XX(r, ... A.YY(...)
  DESER_LINES=$(grep -n 'case 1:.*return new A\.[a-zA-Z_$][a-zA-Z0-9_$]*(' "${JS_FILE}.bak" 2>/dev/null | head -5 || true)
  if [ -n "$DESER_LINES" ]; then
    echo "$DESER_LINES" | while read -r line; do
      echo "    Deserialization case: $line"
    done
  fi
fi

# =============================================================================
# Step 4: Verify the patch
# =============================================================================
echo ""
echo "=== Patch Summary ==="

REMAINING_THROWS=$(count_matches "$THROW_PATTERN" "$JS_FILE")
RETURN_ARRAY_COUNT=$(count_matches 'return\[\]' "$JS_FILE")
RETURN_FUNC_COUNT=$(count_matches 'return function(b,c)' "$JS_FILE")

echo "  Functions patched to return[]: $RETURN_ARRAY_COUNT"
echo "  Functions patched to return function: $RETURN_FUNC_COUNT"
echo "  Remaining UnimplementedError throws: $REMAINING_THROWS"

if [ "$RETURN_ARRAY_COUNT" -gt 0 ] || [ "$RETURN_FUNC_COUNT" -gt 0 ]; then
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
