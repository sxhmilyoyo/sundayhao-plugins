# Common Utilities for Second Brain Plugin

This directory contains shared utilities used by the second-brain plugin skills.

## Overview

Common utilities provide reusable functionality for knowledge bank path discovery and validation.

## Available Utilities

### get_kb_path.sh

**Purpose**: Discovers the knowledge bank path from the plugin configuration file.

**Config Location**: `~/.claude/plugins/config/second-brain/config.json`

**Usage**:
```bash
# In your skill script
source /path/to/common/get_kb_path.sh

# Get the KB path
KB_PATH=$(get_kb_path)

# Validate the path exists
if ! validate_kb_path "$KB_PATH"; then
    exit 1
fi

# Use the path
echo "Knowledge bank: $KB_PATH"
```

**Functions**:
- `get_kb_path()` - Returns the configured knowledge bank path
- `get_plugin_config_value(key, default)` - Returns one config key, falling back on every failure so a broken config disables a feature rather than enabling it
- `validate_kb_path(path)` - Validates that the path exists and is accessible

### resolve_project.sh

**Purpose**: The one place a session's project is derived. `project` names a knowledge-bank **domain**
drawn from the vault's `projects/` folders, never the directory a session ran in (see
`docs/adr/0004-project-names-a-knowledge-bank-domain.md`). Mapped from the working directory through
`project_domains` in the plugin config.

```bash
source resolve_project.sh

resolve_project "/path/to/cwd"      # → a domain, or empty when unmapped
validate_project "$stored_value"    # → the value, or empty when out of set
list_project_domains                # → the domain set, one per line
project_default_tags "/path/to/cwd" # → "tag, tag" hints for the matched prefix
```

A map key matches a directory it equals or contains; a key ending in `*` matches any path beginning
with the stem, which covers a family of sibling packages with one entry. The longest match wins.

Two rules every caller depends on. Anything unmapped resolves to **empty**, so an unrecognised domain
stays visibly missing instead of being invented. Any stored value outside the domain set also resolves
to empty, which is what makes leaving older notes alone safe: a directory basename is non-empty but is
not a domain, and `validate_project` reports it as unresolved without the caller needing to know when
the note was written.

`project_default_tags` is for building a prompt, not for writing to a note. Tags written by a hook
would leave every mapped session already tagged, and the trigger that asks Claude to describe a new
session would never fire.

### launch_delegate.sh

**Purpose**: Start a session that records which session launched it.

```bash
./launch_delegate.sh <role> <prompt>
```

Sets `SECOND_BRAIN_DELEGATED_BY` and `SECOND_BRAIN_DELEGATED_BY_NAME` **inline on the launched
command**, so the delegate's own SessionStart hook records the relationship. Never use a terminal
manager's `--env` option for this: that adds the variable to the pane's root shell, so every later
session in that pane inherits a launcher that never launched it. Under Herdr the script opens a pane;
elsewhere it prints the command to run.

### setup_kb_path.sh

**Purpose**: Interactive configuration tool for setting up the knowledge bank path.

**Usage**:
```bash
# Configure knowledge bank path interactively
./setup_kb_path.sh --configure

# Set one key, preserving every other key in the file
./setup_kb_path.sh --set auto_recap notify

# Map a directory prefix to a domain, with optional default tags
./setup_kb_path.sh --set-domain /path/to/service aax aax
./setup_kb_path.sh --set-domain '/path/to/Service*' aax aax

# Show current configuration, including the domain map
./setup_kb_path.sh --show
./setup_kb_path.sh  # Default: same as --show
```

**Config File Format**:
```json
{
  "version": "1.0",
  "knowledge_bank_path": "/path/to/your/knowledge-bank",
  "configured_at": "2026-01-07T12:00:00Z",
  "project_domains": {
    "/path/to/service": { "domain": "aax", "default_tags": ["aax"] },
    "/path/to/Service*": { "domain": "aax" }
  }
}
```

`--set` and `--set-domain` are read-modify-write and preserve keys they do not know, which is what
other features in this file depend on. `--configure` rewrites only the path and timestamp and leaves
the rest intact for the same reason.

## Configuration

### Via setup_kb_path.sh

Use this directly if you need to change your KB path later:

```bash
./setup_kb_path.sh --configure
```

### Auto-Detection (First Run)

If the KB is not configured when you start Claude Code, the SessionStart hook will prompt you to run the setup.

## Error Handling

Skills that use common utilities fail fast with clear errors:

```bash
# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/get_kb_path.sh"

KB_PATH=$(get_kb_path)
if [ $? -ne 0 ] || [ -z "$KB_PATH" ]; then
    echo "Knowledge bank not configured"
    exit 1
fi
```

## Skills Using Common Utilities

- **session-recap**: Uses `get_kb_path.sh` for knowledge bank location
- **knowledge-bank-lookup**: Uses `get_kb_path.sh` for knowledge bank location
- **Hook scripts**: SessionStart, SessionEnd, PreCompact hooks use `get_kb_path.sh`

## Troubleshooting

### "Knowledge bank not configured" Error

**Cause**: The plugin configuration file doesn't exist or is invalid.

**Solution**:
1. Run the setup script: `setup_kb_path.sh --configure`
2. Enter your knowledge bank path
3. Verify with: `setup_kb_path.sh --show`

### "Knowledge bank directory not found" Error

**Cause**: The configured path doesn't exist.

**Solution**:
1. Check your configuration: `setup_kb_path.sh --show`
2. Verify the path exists: `ls /path/to/knowledge-bank`
3. Re-run configuration if needed: `setup_kb_path.sh --configure`

### Path Detection Not Working

**Debug**: Use the diagnostic tool:
```bash
setup_kb_path.sh --show
```

This will show:
- Config file location
- Configured path
- Whether the path exists
- Project and daily log counts

## Versioning

Common utilities follow semantic versioning:
- **Major**: Breaking changes to function signatures or behavior
- **Minor**: New utilities or non-breaking enhancements
- **Patch**: Bug fixes

Current version: **2.1.0**

## Best Practices

1. **Always validate paths**: Use `validate_kb_path()` after `get_kb_path()`
2. **Fail fast**: Don't provide silent fallbacks in scripts
3. **Clear errors**: Provide actionable error messages with solutions
4. **Document dependencies**: If your script uses common utilities, document it

## License

Internal use only.
