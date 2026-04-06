#!/bin/bash
# Count WikiLinks in a document to verify minimum cross-reference requirements

if [ $# -eq 0 ]; then
    echo "Usage: $0 <markdown-file> [min-links]"
    echo "Counts WikiLinks ([[Link Name]]) in the specified markdown file"
    echo "  min-links: minimum required (default: 10, use 5 for ingested/reference docs)"
    exit 1
fi

FILE="$1"
MIN_LINKS="${2:-10}"

if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' not found"
    exit 1
fi

# Count total WikiLinks
count=$(grep -o '\[\[' "$FILE" | wc -l | tr -d ' ')

echo "=== WikiLink Analysis for $(basename "$FILE") ==="
echo ""
echo "Total WikiLinks: $count"
echo ""

# List all unique WikiLinks
echo "Unique WikiLinks:"
grep -o '\[\[[^]]*\]\]' "$FILE" | sort | uniq | sed 's/^/  - /'
echo ""

# Count by category (rough heuristics)
# Note: These are approximate counts based on naming patterns
components=$(grep -o '\[\[[^]]*\]\]' "$FILE" | grep -iE "plugin|provider|builder|factory|impl|extractor|service|handler|processor" | wc -l | tr -d ' ')
concepts=$(grep -o '\[\[[^]]*\]\]' "$FILE" | grep -iE "pattern|principle|isolation|execution|caching|design|architecture" | wc -l | tr -d ' ')
practices=$(grep -o '\[\[[^]]*\]\]' "$FILE" | grep -iE "methodology|testing|migration|refactoring|optimization|metrics" | wc -l | tr -d ' ')
sessions=$(grep -o '\[\[[^]]*\]\]' "$FILE" | grep -E "20[0-9]{2}-[0-9]{2}-[0-9]{2}" | wc -l | tr -d ' ')
mocs=$(grep -o '\[\[[^]]*\]\]' "$FILE" | grep -iE "MOC|map of content" | wc -l | tr -d ' ')

echo "Category Breakdown (approximate):"
echo "  Components: $components"
echo "  Concepts: $concepts"
echo "  Best Practices: $practices"
echo "  Sessions: $sessions"
echo "  MOCs: $mocs"
echo ""

# Verify minimum requirements
if [ "$count" -lt "$MIN_LINKS" ]; then
    echo "WARNING: Only $count cross-references found (minimum $MIN_LINKS required)"
    exit 1
else
    echo "SUCCESS: $count cross-references found (minimum $MIN_LINKS met)"
fi
