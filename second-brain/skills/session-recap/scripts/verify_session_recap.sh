#!/bin/bash
# Verify session recap completeness before declaring done
# This script enforces the verification gate required by the session-recap skill

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities for dynamic discovery functions
COMMON_DIR="$SCRIPT_DIR/../../common"
if [ -f "$COMMON_DIR/get_kb_path.sh" ]; then
    source "$COMMON_DIR/get_kb_path.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

print_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  SESSION RECAP VERIFICATION"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

print_section() {
    echo "───────────────────────────────────────────────────────────────"
    echo "  $1"
    echo "───────────────────────────────────────────────────────────────"
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    WARNINGS=$((WARNINGS + 1))
}

info() {
    echo -e "  ℹ $1"
}

# Parse arguments
KB_PATH=""
PROJECT=""
DAILY_LOG=""
REFLECTION_REQUIRED="unknown"
PROPOSALS="unset"
CREATED_DOCS=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --kb-path PATH          Knowledge bank path (required)"
    echo "  --project PROJECT       Project name (auto-discovered from knowledge bank)"
    echo "  --daily-log FILE        Path to created daily log"
    echo "  --reflection-required   Flag that reflection is required (problem-solving occurred)"
    echo "  --no-reflection         Flag that reflection is NOT required"
    echo "  --proposals F1,F2,...   Proposal files the Phase 2.7 scan produced (filenames in _proposals/)"
    echo "  --no-proposals          Flag that the Phase 2.7 scan found no candidates"
    echo "  --docs FILE1,FILE2,...  Comma-separated list of created documentation files"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --kb-path /path/to/kb --project my-project --daily-log '2024-01-15 Session.md' --reflection-required"
    echo "  $0 --kb-path /path/to/kb --project tooling --daily-log '2024-01-15 Session.md' --no-reflection"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --kb-path)
            KB_PATH="$2"
            shift 2
            ;;
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --daily-log)
            DAILY_LOG="$2"
            shift 2
            ;;
        --reflection-required)
            REFLECTION_REQUIRED="yes"
            shift
            ;;
        --no-reflection)
            REFLECTION_REQUIRED="no"
            shift
            ;;
        --proposals)
            PROPOSALS="$2"
            shift 2
            ;;
        --no-proposals)
            PROPOSALS="none"
            shift
            ;;
        --docs)
            CREATED_DOCS="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$KB_PATH" ]; then
    echo "Error: --kb-path is required"
    usage
    exit 1
fi

if [ ! -d "$KB_PATH" ]; then
    echo "Error: Knowledge bank path does not exist: $KB_PATH"
    exit 1
fi

print_header

# ═══════════════════════════════════════════════════════════════
# SECTION 1: Daily Log Verification
# ═══════════════════════════════════════════════════════════════
print_section "1. DAILY LOG VERIFICATION"

if [ -n "$DAILY_LOG" ]; then
    LOG_PATH="$KB_PATH/daily-log/$DAILY_LOG"
    if [ -f "$LOG_PATH" ]; then
        pass "Daily log exists: $DAILY_LOG"

        # Count cross-references in daily log
        LINK_COUNT=$(grep -o '\[\[' "$LOG_PATH" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$LINK_COUNT" -ge 10 ]; then
            pass "Daily log has $LINK_COUNT cross-references (minimum: 10)"
        else
            fail "Daily log has only $LINK_COUNT cross-references (minimum: 10)"
        fi

        # Check frontmatter
        if grep -q "^---$" "$LOG_PATH"; then
            pass "Daily log has YAML frontmatter"
        else
            fail "Daily log missing YAML frontmatter"
        fi
    else
        fail "Daily log not found: $LOG_PATH"
    fi
else
    fail "No daily log specified (use --daily-log)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# SECTION 2: Reflection Decision Gate
# ═══════════════════════════════════════════════════════════════
print_section "2. REFLECTION DECISION GATE"

if [ "$REFLECTION_REQUIRED" = "unknown" ]; then
    warn "Reflection requirement not specified"
    info "Use --reflection-required if problem-solving occurred"
    info "Use --no-reflection if session was simple edits only"
elif [ "$REFLECTION_REQUIRED" = "yes" ]; then
    info "Problem-solving detected → reflection REQUIRED"

    # Discover reflection directories dynamically
    REFLECTIONS_PATH="$KB_PATH/reflections"
    REFLECTION_DIRS=()
    if [ -d "$REFLECTIONS_PATH" ]; then
        if type discover_categories &>/dev/null; then
            mapfile -t REFLECTION_DIRS < <(discover_categories "$REFLECTIONS_PATH" 2>/dev/null)
        else
            # Fallback: find subdirectories manually
            mapfile -t REFLECTION_DIRS < <(find "$REFLECTIONS_PATH" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null)
        fi
    fi

    REFLECTION_FOUND=0

    for dir in "${REFLECTION_DIRS[@]}"; do
        REFLECTION_PATH="$REFLECTIONS_PATH/$dir"
        if [ -d "$REFLECTION_PATH" ]; then
            # Check for recently created files (within last hour)
            RECENT_FILES=$(find "$REFLECTION_PATH" -name "*.md" -mmin -60 2>/dev/null | wc -l | tr -d ' ')
            if [ "$RECENT_FILES" -gt 0 ]; then
                REFLECTION_FOUND=$((REFLECTION_FOUND + RECENT_FILES))
                pass "Found $RECENT_FILES recent reflection(s) in $dir/"
            fi
        fi
    done

    if [ "$REFLECTION_FOUND" -eq 0 ]; then
        # Also check for any reflections created today
        TODAY=$(date +%Y-%m-%d)
        for dir in "${REFLECTION_DIRS[@]}"; do
            REFLECTION_PATH="$REFLECTIONS_PATH/$dir"
            if [ -d "$REFLECTION_PATH" ]; then
                TODAY_FILES=$(find "$REFLECTION_PATH" -name "*.md" -newer /tmp/.yesterday_marker 2>/dev/null | wc -l | tr -d ' ')
                REFLECTION_FOUND=$((REFLECTION_FOUND + TODAY_FILES))
            fi
        done

        if [ "$REFLECTION_FOUND" -eq 0 ]; then
            fail "No reflections found but problem-solving occurred (MUST create at least 1)"
        else
            pass "Found reflections created today"
        fi
    fi
elif [ "$REFLECTION_REQUIRED" = "no" ]; then
    pass "No reflection required (simple session)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# SECTION 3: Proposed Improvements (Phase 2.7 consistency)
# ═══════════════════════════════════════════════════════════════
print_section "3. PROPOSED IMPROVEMENTS"

# Consistency, not existence: zero candidates is a legitimate scan outcome, so the
# check is that the scan's recorded result and the files in _proposals/ agree, and
# that each file is a complete, pending proposal a person can act on.
if [ "$PROPOSALS" = "unset" ]; then
    warn "Improvement scan outcome not specified"
    info "Use --proposals file1,file2 for the files the Phase 2.7 scan produced"
    info "Use --no-proposals when the scan found no candidates"
elif [ "$PROPOSALS" = "none" ]; then
    pass "Improvement scan recorded no candidates (a legitimate outcome)"
else
    IFS=',' read -ra PROP_ARRAY <<< "$PROPOSALS"
    for prop in "${PROP_ARRAY[@]}"; do
        prop=$(echo "$prop" | xargs)
        [ -n "$prop" ] || continue
        BASENAME=$(basename "$prop")
        PROP_PATH="$KB_PATH/_proposals/$BASENAME"
        if [ ! -f "$PROP_PATH" ]; then
            fail "$BASENAME: recorded by the scan but not found in _proposals/"
            continue
        fi
        FM=$(sed -n '/^---$/,/^---$/p' "$PROP_PATH")
        MISSING=""
        for field in type severity category target classification session-folder status; do
            printf '%s\n' "$FM" | grep -q "^$field:" || MISSING="$MISSING $field"
        done
        # Values may arrive quoted or bare: Obsidian strips quotes it does not need
        # whenever a person saves a note, the same drift the session-note scan accepts.
        if [ -n "$MISSING" ]; then
            fail "$BASENAME: frontmatter missing:$MISSING"
        elif ! printf '%s\n' "$FM" | grep -Eq '^type:[[:space:]]*"?proposed-improvement"?[[:space:]]*$'; then
            fail "$BASENAME: type must be proposed-improvement"
        elif ! printf '%s\n' "$FM" | grep -Eq '^severity:[[:space:]]*"?(critical|high|medium|low)"?[[:space:]]*$'; then
            fail "$BASENAME: severity must be critical, high, medium or low"
        elif ! printf '%s\n' "$FM" | grep -Eq '^classification:[[:space:]]*"?(mechanical|judgment)"?[[:space:]]*$'; then
            fail "$BASENAME: classification must be mechanical or judgment"
        elif ! printf '%s\n' "$FM" | grep -Eq '^status:[[:space:]]*"?pending"?[[:space:]]*$'; then
            fail "$BASENAME: a recap writes proposals as status: pending; only a person moves them"
        else
            pass "$BASENAME: complete proposal, pending"
        fi
    done
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# SECTION 4: Cross-Reference Validation
# ═══════════════════════════════════════════════════════════════
print_section "4. CROSS-REFERENCE VALIDATION"

if [ -n "$CREATED_DOCS" ]; then
    IFS=',' read -ra DOC_ARRAY <<< "$CREATED_DOCS"
    for doc in "${DOC_ARRAY[@]}"; do
        doc=$(echo "$doc" | xargs)  # Trim whitespace
        if [ -f "$doc" ]; then
            LINK_COUNT=$(grep -o '\[\[' "$doc" 2>/dev/null | wc -l | tr -d ' ')
            BASENAME=$(basename "$doc")

            # Determine minimum based on doc type
            if echo "$doc" | grep -q "reflections"; then
                MIN_LINKS=5
            else
                MIN_LINKS=10
            fi

            if [ "$LINK_COUNT" -ge "$MIN_LINKS" ]; then
                pass "$BASENAME: $LINK_COUNT cross-references (minimum: $MIN_LINKS)"
            else
                fail "$BASENAME: only $LINK_COUNT cross-references (minimum: $MIN_LINKS)"
            fi
        else
            warn "Document not found: $doc"
        fi
    done
else
    info "No additional docs specified for verification (use --docs)"
fi

# Run WikiLink validation if validate_cross_references.sh exists
if [ -f "$SCRIPT_DIR/validate_cross_references.sh" ] && [ -n "$DAILY_LOG" ]; then
    LOG_PATH="$KB_PATH/daily-log/$DAILY_LOG"
    if [ -f "$LOG_PATH" ]; then
        info "Running WikiLink validation on daily log..."
        BROKEN_LINKS=$("$SCRIPT_DIR/validate_cross_references.sh" "$LOG_PATH" 2>/dev/null | grep -c "NOT FOUND" || true)
        if [ "$BROKEN_LINKS" -eq 0 ]; then
            pass "No broken WikiLinks detected"
        else
            warn "$BROKEN_LINKS broken WikiLink(s) detected"
        fi
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# SECTION 5: Summary
# ═══════════════════════════════════════════════════════════════
print_section "VERIFICATION SUMMARY"

echo ""
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ ALL CHECKS PASSED - Session recap may be declared complete${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    exit 0
elif [ "$ERRORS" -eq 0 ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  ⚠ PASSED WITH $WARNINGS WARNING(S)${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    exit 0
else
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  ✗ VERIFICATION FAILED: $ERRORS error(s), $WARNINGS warning(s)${NC}"
    echo -e "${RED}  DO NOT declare session recap complete until errors are fixed${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    exit 1
fi
