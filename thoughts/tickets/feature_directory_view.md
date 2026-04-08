---
type: feature
priority: medium
created: 2026-04-08T12:00:00Z
created_by: Opus
status: planned
tags: [fzf, directory-view, preview]
keywords: [sort, directory, unique, preview, fzf]
patterns: [sorting logic, preview window, bash functions]
---

# FEATURE-001: Add directory view with unique directory listing and session preview

## Description

Enhance the existing --sort directory functionality to:
1. Show unique directories with session counts (not just sorted sessions)
2. Add preview that shows all sessions within the selected directory

## Context

Users have many sessions across multiple projects. Currently, sorting by "directory" sorts alphabetically but doesn't group unique directories together. Users want to:
1. See unique directories with session counts
2. Preview all sessions in a selected directory
3. Select a specific session from that directory to resume

## Requirements

### Functional Requirements

1. **Modify --sort directory** (existing option)
   - Change from sorted sessions to unique directories with counts
   - Format: "~/projects/myapp (3 sessions)" 
   - Display directory paths with session count per directory

2. **Add preview for directory view**
   - When a directory is selected in --sort directory mode
   - Preview shows list of all sessions in that directory
   - Preview displays: session title, status icon, time ago, model

3. **--dir <name>** (new filter option)
   - Takes a directory name/path as argument
   - Shows sessions list filtered to that directory only
   - SQL: `AND s.directory = '$DIR_FILTER'` (exact match)
   - Works like default view but filtered

4. **Dynamic Header** (replaces footer)
   - Replace --footer with --header showing current sort, session count, time range
   - Works with all views

### Non-Functional Requirements

- Maintain existing performance (fast directory grouping)
- Consistent with existing UI/UX patterns (colors, icons)
- Works with --multi mode

## Current State

- Has --sort directory option (sorts sessions by repo name)
- Currently shows individual sessions sorted by directory
- Uses --footer for sort cycling hint
- No --dir filter option exists
- No unique directory grouping

## Desired State

1. **--sort directory** - Shows unique directories with session counts
   - Display format: "🟢  5m ago  myproject (3 sessions)"
   - Status from latest session in directory (using compute_status)
   - Time_ago from latest session in directory
   - Number of sessions count
   - Short name (use derive_repo_name())
   - Sort by newest: use MAX(time_updated) from sessions in each directory
2. **Directory Preview** - When directory selected, preview shows sessions in that directory
   - List all sessions in the selected directory
   - Display format per session: "🟡  10m ago  Working on feature X [model-name]"
   - Shows: status icon, time_ago, session title, model
   - Scrollable if many sessions

4. **Dynamic Preview** - Preview command receives sort type as argument
   - Pass sort mode to preview: `--preview "bash '${PREVIEW_SCRIPT}' {} ${SORT_BY}"`
   - preview.sh checks second argument to determine output format
   - If sort=directory → show directory sessions list
   - Otherwise → show session details (current behavior)
3. **--dir <name>** - Filter sessions by specific directory
4. **Dynamic Header** - Replace footer with header

## Research Context

### Keywords to Search

- sort_by_directory - Existing sort function to modify
- preview.sh - Existing preview script to extend or reference
- format_for_display - Display formatting function
- fzf --preview - Preview window integration patterns
- unique directories - Grouping logic needed

### Patterns to Investigate

- sort logic - How sort_by_directory currently works
- preview integration - How preview.sh is called with fzf
- fzf delimiter - How to extract directory from fzf line
- status display - Existing status icon patterns

### Key Decisions Made

- Modify existing --sort directory to show unique directories (not sorted sessions)
- Use awk/groupby to consolidate sessions into directory entries with counts
- Add directory preview to show sessions in selected directory
- --dir uses SQL exact match: `s.directory = '$DIR_FILTER'`
- Dynamic header replaces footer

## Success Criteria

### Automated Verification

- [ ] --sort dirs shows unique directories with session counts
- [ ] Directory count displays correctly (e.g., "(3 sessions)")
- [ ] Preview shows sessions in selected directory
- [ ] --dir <name> filters to specific directory (exact match)
- [ ] Filtered view shows only sessions in that directory
- [ ] Dynamic header replaces footer in all views
- [ ] Header shows: sort mode, session count, time range

### Manual Verification

- [ ] Default view unchanged (shows sessions list)
- [ ] --sort dirs shows directory grouping
- [ ] --dir option filters by exact directory match
- [ ] Works with --days and --all filters
- [ ] Dynamic header visible in all views

## Related Information

- Existing script: opencode-sessions-fzf.sh (605 lines)
- Existing preview: preview.sh
- Related sort: sort_by_directory function (lines 330-332)

## Notes

- Consider whether to show parent directories or full paths
- Need to handle directories with many sessions gracefully
- Should the preview support scrolling for many sessions?
