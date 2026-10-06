
## Data Expectations from Database Queries (v1)

### Main session query returns (in order):
- id
- title
- directory
- time_updated
- time_created
- worktree
- project_name
- last_role
- last_completed
- has_running_question
- has_child_question
- has_error
- child_count
- model

These are pipe (|) delimited, e.g.:
```
id|title|directory|time_updated|...|model
```

### Directory-level query returns:
- directory
- session_count
- latest_time
- latest_role
- latest_completed

### Derived Field Logic (used downstream)
- `status` = computed from role, question/error state, etc.
- Model, repo/project, title parsed or truncated for display

---

## Output
- All DB layer output is pipe-delimited, fields in strict order
- Formatting expects exact field order as above
- Downstream parsing uses IFS='|'

---

### (TO UPDATE FOR v2)
- Fill in new structure when v2 is live
- Note changes to field meaning, nullability, messages/parts→event rows, etc.
