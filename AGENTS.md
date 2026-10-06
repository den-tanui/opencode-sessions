
## Data Expectations from Database Queries (v2)

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

### v2 Schema Notes

- **Tables:** `session_v2`, `session_message`, `project` (no `part` table)
- **`last_role`:** comes from `session_message.type` column (not `json_extract($.role)`)
- **`last_completed`:** `json_extract(session_message.data, '$.time.completed')`
- **`model`:** extracted from `session_v2.model` JSON column via `json_extract($.id)` — raw value is a JSON object like `{"id":"big-pickle","providerID":"opencode","variant":"default"}`
- **`has_running_question` / `has_child_question` / `has_error`:** use `json_each(session_message.data, '$.content')` to inspect tool items in assistant messages — fields are `$.type='tool'`, `$.name` (was `$.tool` in v1), `$.state.status`
- **`child_count`:** `COUNT(*) FROM session_v2 WHERE parent_id = s.id AND time_archived IS NULL`

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

### v1 → v2 Migration Reference

| v1 | v2 | Notes |
|---|---|---|
| `session` table | `session_v2` table | Renamed |
| `message` table | `session_message` table | Renamed |
| `part` table | gone | Parts now embedded in `session_message.data` JSON `content` array |
| `json_extract(data, '$.role')` | `session_message.type` column | Direct column, no JSON extraction |
| `json_extract(data, '$.modelID')` | `json_extract(session_v2.model, '$.id')` | Model is JSON object on session, not message |
| `json_extract(p.data, '$.type') = 'tool'` | `json_extract(value, '$.type') = 'tool'` via `json_each` | Nested in content array |
| `json_extract(p.data, '$.tool')` | `json_extract(value, '$.name')` | Field renamed from `tool` to `name` |
| `json_extract(p.data, '$.state.status')` | `json_extract(value, '$.state.status')` via `json_each` | Nested in content array |
| `json_extract(p.data, '$.text')` (text part) | `json_extract(value, '$.text')` via `json_each` on `$.content` | For assistant messages |
| `json_extract(p.data, '$.text')` (text part) | `json_extract(data, '$.text')` | For user/system/synthetic messages (flat JSON) |
