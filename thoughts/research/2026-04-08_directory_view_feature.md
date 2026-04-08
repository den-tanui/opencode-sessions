---
date: 2026-04-08T16:58:21+03:00
git_commit: 976ef3924e34111f43bac8ecbb2e747a909ad03e
branch: main
repository: opencode-multiplexer
topic: "Directory view feature for opencode-sessions-fzf.sh"
tags: [research, fzf, bash, directory-view, sorting]
last_updated: 2026-04-08
last_updated_note: "Updated to reflect simplified approach: modify existing --sort directory, add dynamic preview with sort type argument"
---

## Ticket Synopsis

**Ticket:** FEATURE-001  
**Type:** Feature (directory view with unique directories and dynamic header)  
**Priority:** Medium

Enhance existing --sort directory to show unique directories with session counts and add preview that shows sessions within selected directory. Also add --dir filter option and dynamic header replacing footer.

## Summary

Research analyzed the existing opencode-sessions-fzf.sh script. The feature requires:

1. **Modify --sort directory** - Group sessions by unique directories with counts
   - Sort by newest: use MAX(time_updated) from each directory's sessions
2. **Dynamic preview** - Pass sort type to preview: `--preview "bash '${PREVIEW_SCRIPT}' {} ${SORT_BY}"`
   - preview.sh checks sort type, shows directory sessions if sort=directory
3. **Directory display format** - "🟢 5m ago myproject (3 sessions)" (status from latest session)
4. **Directory preview format** - List sessions: "🟡 10m ago Working on feature X [model-name]"
5. **--dir filter** - SQL exact match: `s.directory = '$DIR_FILTER'`
6. **Dynamic header** - Replace footer with --header showing sort/count/range

## Detailed Findings

### Current Implementation

**Main Script: `opencode-sessions-fzf.sh`**

- **Sort options** (lines 354-361): time, directory, status
- **Current sort_by_directory** (lines 330-332): Sorts by repo name (field 4), then by time (field 9)
- **Fzf configuration** (lines 527-541):
  ```bash
  fzf \
      --height 80% \
      --ansi \
      --layout=reverse \
      --border \
      --with-nth 2.. \
      --preview "bash '${PREVIEW_SCRIPT}' {}" \
      --preview-window "right:60%,border-left" \
      --delimiter '\t' \
      --prompt="Select session: " \
      --footer "Alt-S: cycle sort (→ $(get_sort_label "$SORT_BY")) | ..."
  ```

**Preview Script: `preview.sh`**

- Takes tab-delimited fzf line, extracts session_id from first field
- Shows session details: title, ID, status, model, directory, time, children, last message, modified files

### Key Components to Modify

| Component | Location | Change Required |
|-----------|----------|-----------------|
| Argument parsing | Lines 37-86 | Add `--dir` option |
| SQL query | Lines 199-200 | Add `AND s.directory = '$DIR_FILTER'` |
| Sort functions | Lines 325-361 | Modify for directory grouping with counts |
| Build session data | Lines 293-321 | Group by unique directory |
| Fzf call | Lines 527-541 | Replace --footer with --header, pass SORT_BY to preview |
| Preview script | preview.sh | Accept second arg (sort type), show directory sessions if directory |

### Dynamic Preview Implementation

```bash
# In fzf call, pass sort type as second argument:
--preview "bash '${PREVIEW_SCRIPT}' {} ${SORT_BY}" \

# In preview.sh, check second argument:
SORT_TYPE="${2:-}"
if [[ "$SORT_TYPE" == "directory" ]]; then
    # Show directory sessions list
    ...
else
    # Show session details (current behavior)
    ...
fi
```

### SQL Implementation for --dir

```bash
# In query_all_sessions function, add to WHERE clause:
AND s.directory = '${DIR_FILTER}'
```

This is a simple exact match filter - no LIKE needed.

### Fzf Header Pattern

From research, dynamic header pattern:

```bash
header="Sort: ${current_sort} | Sessions: ${count} | Range: ${days}d"

format_for_display <"$sorted_file" | fzf \
    --header="$header" \
    --preview "bash '${PREVIEW_SCRIPT}' {}" \
    ...
```

### Two-Stage Selection Flow

1. Show directory view (unique dirs with counts)
2. User selects a directory
3. Extract directory path from selection
4. Re-run fzf with `--dir <selected_directory>`
5. User picks session to resume

## Code References

- `opencode-sessions-fzf.sh:37-86` - Argument parsing (add --dir here)
- `opencode-sessions-fzf.sh:199-200` - SQL WHERE clause (add directory filter)
- `opencode-sessions-fzf.sh:293-321` - build_session_data() (modify for directory grouping)
- `opencode-sessions-fzf.sh:325-361` - Sort functions (add dirview type)
- `opencode-sessions-fzf.sh:527-541` - Fzf call (replace --footer with --header)
- `opencode-sessions-fzf.sh:543-593` - Selection handling (add two-stage logic)
- `preview.sh:24-30` - Input parsing (session_id extraction)
- `thoughts/tickets/feature_directory_view.md` - Feature ticket

## Architecture Insights

- Session data flows: query_all_sessions → build_session_data → sort_data → format_for_display → fzf
- Tab-delimiter used throughout for field parsing
- Status computed from: has_running_question, has_child_question, has_error, last_role, last_completed
- Cycle script (lines 464-523) handles sort cycling via reload binding
- Two-stage requires: store selected directory, re-invoke script or re-run fzf with filtered data

## Historical Context

- `thoughts/tickets/debt_sql_performance.md` - Previous SQL optimization work
- Existing sort options: time (default), directory (alphabetical), status
- Current footer shows: "Alt-S: cycle sort | navigation | Enter: resume | ?: toggle preview"

## Open Questions

1. Should directory view also be cyclable via Alt-S (add to sort_order)?
2. How to handle very long directory paths in display (truncate or show full)?
3. Should --dir option work standalone (without directory view)?