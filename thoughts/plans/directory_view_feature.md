# Directory View Feature Implementation Plan

## Overview

Implement enhanced directory functionality in opencode-sessions-fzf.sh: modify --sort directory to show unique directories with session counts, add --dir filter option, and replace footer with dynamic header.

## Current State Analysis

- **Sort options** (lines 354-361): time, directory, status
- **sort_by_directory** (lines 330-332): Sorts individual sessions by repo name, not directories
- **Fzf call** (lines 527-541): Uses `--footer` for sort hint, static preview
- **No --dir option**: Directory filtering not implemented

## Desired End State

1. `--sort directory` shows unique directories with session counts
2. Preview shows sessions in selected directory when in directory view
3. `--dir <name>` filters sessions to specific directory
4. Dynamic `--header` replaces `--footer`

### Key Discoveries:
- `compute_status()` function (line 258-271) can be reused for directory status
- `derive_repo_name()` (line 220-227) extracts short name from directory path
- `status_icon()` (line 273-281) provides colored status icons
- Cycle script (lines 464-523) handles sort cycling via reload binding

## Implementation Approach

1. **Phase 1**: Add `--dir` option (simplest, standalone)
2. **Phase 2**: Modify directory sorting for unique directory grouping
3. **Phase 3**: Add dynamic preview with sort type argument
4. **Phase 4**: Replace footer with dynamic header

## What We're NOT Doing

- Two-stage selection (directory → session picker) - not implementing
- Parent directory navigation - showing full paths not planned
- Multi-select in directory view - only single selection supported

---

## Phase 1: Add --dir Filter Option

### Overview
Add `--dir` CLI option to filter sessions by exact directory match.

### Changes Required:

#### 1. Argument Parsing
**File**: `opencode-sessions-fzf.sh:37-86`
**Changes**: Add `--dir` case in argument parsing

```bash
--dir)
    DIR_FILTER="$2"
    shift 2
    ;;
```

#### 2. SQL Query Modification
**File**: `opencode-sessions-fzf.sh:199-200`
**Changes**: Add directory filter to WHERE clause

```bash
WHERE s.time_archived IS NULL AND s.parent_id IS NULL
  AND s.time_updated >= $time_threshold
  AND s.directory = '${DIR_FILTER}';
```

#### 3. Help Text Update
**File**: `opencode-sessions-fzf.sh:67-79`
**Changes**: Add --dir to help output

```bash
echo "  --dir DIR       Filter by specific directory (exact match)"
```

### Success Criteria:

#### Automated Verification:
- [ ] Script accepts --dir argument without error
- [ ] SQL filter applied correctly in query
- [ ] Only sessions from matching directory shown

#### Manual Verification:
- [ ] `./opencode-sessions-fzf.sh --dir /path/to/project` shows only that directory's sessions
- [ ] Works with --sort and --days options
- [ ] Error handling for non-existent directory

---

## Phase 2: Modify --sort directory for Unique Directories

### Overview
Change sort_by_directory to group sessions by unique directory with counts using SQL GROUP BY.

### Changes Required:

#### 1. New SQL Query for Directory Grouping
**File**: `opencode-sessions-fzf.sh` (add new function)
**Changes**: Create query_directories() function

```bash
query_directories() {
    local time_threshold
    if [[ "$SHOW_ALL" == "true" ]]; then
        time_threshold=0
    else
        time_threshold=$((($(date +%s) - DAYS_FILTER * 86400) * 1000))
    fi
    
    sqlite3 -separator '|' "$DB_PATH" "
    SELECT s.directory, 
           COUNT(*) as session_count,
           MAX(s.time_updated) as latest_time,
           (SELECT json_extract(m.data, '$.role') 
            FROM message m 
            WHERE m.session_id = (
                SELECT id FROM session 
                WHERE directory = s.directory 
                ORDER BY time_updated DESC LIMIT 1
            )
            ORDER BY time_created DESC LIMIT 1) as latest_role,
           (SELECT json_extract(m.data, '$.time.completed') 
            FROM message m 
            WHERE m.session_id = (
                SELECT id FROM session 
                WHERE directory = s.directory 
                ORDER BY time_updated DESC LIMIT 1
            )
            ORDER BY time_created DESC LIMIT 1) as latest_completed
    FROM session s
    WHERE s.time_archived IS NULL 
      AND s.parent_id IS NULL
      AND s.time_updated >= $time_threshold
    GROUP BY s.directory
    ORDER BY latest_time DESC;
    "
}
```

#### 2. Build Directory Data Function
**File**: `opencode-sessions-fzf.sh` (add new function)
**Changes**: Create build_directory_data() function

```bash
build_directory_data() {
    query_directories | while IFS='|' read -r directory count time_updated role completed; do
        local status
        status=$(compute_status 0 0 0 "$role" "$completed")
        local time_ago
        time_ago=$(relative_time "$time_updated")
        local repo
        repo=$(derive_repo_name "$directory")
        
        printf '%s\t%s\t%s\t%s\t(%d sessions)\t%s\n' \
            "$directory" "$status" "$time_ago" "$repo" "$count" "$time_updated"
    done
}
```

#### 3. Update sort_data Function
**File**: `opencode-sessions-fzf.sh:354-361`
**Changes**: Handle directory sort differently

```bash
sort_data() {
    case "$1" in
        time) sort_by_time ;;
        directory) cat ;;  # Already sorted by SQL
        status) sort_by_status ;;
        *) sort_by_time ;;
    esac
}
```

### Success Criteria:

#### Automated Verification:
- [ ] --sort directory shows unique directories (not duplicate sessions)
- [ ] Each directory shows session count in parentheses
- [ ] Directories sorted by newest session (MAX time_updated)

#### Manual Verification:
- [ ] Directory view shows "🟢 5m ago myproject (3 sessions)" format
- [ ] Short name displayed (not full path)
- [ ] Status from latest session in directory

---

## Phase 3: Dynamic Preview with Sort Type

### Overview
Pass sort type to preview script so it can show different content.

### Changes Required:

#### 1. Fzf Preview Call
**File**: `opencode-sessions-fzf.sh:533`
**Changes**: Pass SORT_BY as second argument

```bash
--preview "bash '${PREVIEW_SCRIPT}' {} ${SORT_BY}" \
```

#### 2. Preview Script Update
**File**: `preview.sh`
**Changes**: Accept second argument, show directory sessions if sort=directory

```bash
SORT_TYPE="${2:-}"
if [[ "$SORT_TYPE" == "directory" ]]; then
    # Extract directory from first field
    DIR="${INPUT%%	*}"
    # Query all sessions in this directory
    SESSIONS=$(sqlite3 ... "WHERE s.directory = '${DIR}' ...")
    # Display: "🟡 10m ago Working on feature X [model-name]"
    echo "$SESSIONS" | while read -r session; do
        printf '%s\t%s\t%s\t%s [%s]\n' "$status_icon" "$time_ago" "$title" "$model"
    done
else
    # Existing session detail preview
    ...
fi
```

### Success Criteria:

#### Automated Verification:
- [ ] Preview receives sort type as second argument
- [ ] Directory view preview shows session list

#### Manual Verification:
- [ ] When --sort directory, preview shows sessions in selected directory
- [ ] Preview format: "🟡 10m ago Working on feature X [model-name]"
- [ ] Regular sort modes show existing preview

---

## Phase 4: Dynamic Header Replacing Footer

### Overview
Replace --footer with --header showing current sort, session count, time range.

### Changes Required:

#### 1. Build Dynamic Header
**File**: `opencode-sessions-fzf.sh` (add before fzf call)
**Changes**: Create header string

```bash
# Build dynamic header
range_label="$([ "$SHOW_ALL" == "true" ] && echo "all" || echo "${DAYS_FILTER}d")"
header="Sort: $(get_sort_label "$SORT_BY") | Sessions: ${filtered_count} | Range: ${range_label}"
```

#### 2. Replace Footer with Header
**File**: `opencode-sessions-fzf.sh:537`
**Changes**: Change --footer to --header

```bash
--header="$header" \
--footer "↑/↓: navigate | Enter: resume | ?: toggle preview" \
```

### Success Criteria:

#### Automated Verification:
- [ ] Header displays with correct format
- [ ] Session count accurate
- [ ] Time range shows "14d" or "all"

#### Manual Verification:
- [ ] Header visible at top of fzf
- [ ] Format: "Sort: time | Sessions: 12 | Range: 14d"
- [ ] Works with all sort modes

---

## Phase 5: Update Cycle Script for Directory View

### Overview
Update the sort cycling script to handle directory view data format.

### Changes Required:

#### 1. Update Cycle Script
**File**: `opencode-sessions-fzf.sh:464-523`
**Changes**: Handle directory sort in cycle script

```bash
# In cycle_script, update sort_data function:
sort_data() {
    case "\$1" in
        time) cat ;;
        directory) cat ;;  # Already grouped and sorted
        status)
            while IFS=\$'\t' read -r id status time_ago repo title model directory child_count; do
                local prio
                case "\$status" in
                    working) prio=0 ;;
                    idle) prio=1 ;;
                    *) prio=2 ;;
                esac
                printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "\$id" "\$prio" "\$time_ago" "\$repo" "\$title" "\$model" "\$directory" "\$child_count"
            done | sort -t\$'\t' -k2,2n -k3,3 | while IFS=\$'\t' read -r id prio time_ago repo title model directory child_count; do
                local actual_status
                case "\$prio" in
                    0) actual_status="working" ;;
                    1) actual_status="idle" ;;
                    *) actual_status="dead" ;;
                esac
                printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "\$id" "\$actual_status" "\$time_ago" "\$repo" "\$title" "\$model" "\$directory" "\$child_count"
            done
        ;;
    esac
}
```

#### 2. Update sort_order Array
**File**: `opencode-sessions-fzf.sh:469`
**Changes**: Ensure directory is in cycle order

```bash
sort_order=("time" "directory" "status")
```

### Success Criteria:

#### Automated Verification:
- [ ] Alt-S cycles through all three sort modes
- [ ] Directory view works after cycling
- [ ] Data format preserved during cycling

#### Manual Verification:
- [ ] Press Alt-S to cycle: time → directory → status → time
- [ ] Directory view shows correctly after cycling
- [ ] Preview updates correctly when sort changes

### Manual Testing Steps:
1. Run `./opencode-sessions-fzf.sh` - default view works
2. Run `./opencode-sessions-fzf.sh --sort directory` - shows directory grouping
3. Run `./opencode-sessions-fzf.sh --dir /path/to/project` - filters to directory
4. Run `./opencode-sessions-fzf.sh --sort directory` - preview shows session list
5. Run with `--days 7` - filter works
6. Run with `--all` - shows all sessions
7. Cycle sort with Alt-S - works in all views
8. Check header shows correct info

### Edge Cases:
- Empty directory (0 sessions)
- Directory with many sessions (scrollable preview)
- Non-existent directory with --dir
- Works with --copy and --multi modes

## Migration Notes

- No data migration needed (all changes are functional)
- Existing behavior for --sort time and --sort status unchanged
- Backwards compatible for users not using new features

## References

- Original ticket: `thoughts/tickets/feature_directory_view.md`
- Related research: `thoughts/research/2026-04-08_directory_view_feature.md`
- Existing sort: `opencode-sessions-fzf.sh:330-332`
- Current fzf call: `opencode-sessions-fzf.sh:527-541`