# opencode.db Schema

This document describes the SQLite database schema used by opencode, located at
`~/.local/share/opencode/opencode.db`.

All timestamps are stored as Unix epoch milliseconds (`integer`) unless otherwise noted.

---

## Tables

### `project`

Represents a project (typically a Git repository or working directory).

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique project identifier |
| `worktree` | text | no | — | Worktree path |
| `vcs` | text | yes | — | Version control system (e.g. `git`) |
| `name` | text | yes | — | Project display name |
| `icon_url` | text | yes | — | URL to project icon |
| `icon_color` | text | yes | — | Icon color |
| `time_created` | integer | no | — | Creation timestamp (ms) |
| `time_updated` | integer | no | — | Last update timestamp (ms) |
| `time_initialized` | integer | yes | — | Initialization timestamp (ms) |
| `sandboxes` | text | no | — | JSON array of sandbox configs |
| `commands` | text | yes | — | JSON of custom commands |
| `icon_url_override` | text | yes | — | User-set icon URL override |
| `time_active` | integer | no | `0` | Cumulative active time (ms) |

**Indexes:** none

---

### `session_v2`

Represents an AI chat session within a project. This is the primary session table (v2).

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique session identifier |
| `project_id` | text FK → `project.id` | no | — | Parent project |
| `workspace_id` | text FK → `workspace.id` | yes | — | Associated workspace |
| `parent_id` | text | yes | — | Parent session ID (for sub-sessions) |
| `fork_session_id` | text | yes | — | Session this was forked from |
| `fork_boundary` | text | yes | — | Fork boundary reference |
| `slug` | text | no | — | URL-safe slug |
| `directory` | text | no | — | Working directory for the session |
| `path` | text | yes | — | Filesystem path |
| `title` | text | yes | — | Session title |
| `version` | text | no | — | Schema/app version when created |
| `share_url` | text | yes | — | Public share URL |
| `summary_additions` | integer | yes | — | Lines added (code summary) |
| `summary_deletions` | integer | yes | — | Lines deleted (code summary) |
| `summary_files` | integer | yes | — | Files changed (code summary) |
| `summary_diffs` | text | yes | — | JSON of diff summaries |
| `metadata` | text | yes | — | JSON blob of session metadata |
| `cost` | real | no | `0` | Total cost in USD |
| `tokens_input` | integer | no | `0` | Input tokens consumed |
| `tokens_output` | integer | no | `0` | Output tokens consumed |
| `tokens_reasoning` | integer | no | `0` | Reasoning tokens consumed |
| `tokens_cache_read` | integer | no | `0` | Cache-read tokens |
| `tokens_cache_write` | integer | no | `0` | Cache-write tokens |
| `revert` | text | yes | — | Revert state info |
| `permission` | text | yes | — | Permission mode |
| `agent` | text | yes | — | Agent identifier |
| `model` | text | yes | — | Model identifier (e.g. `claude-sonnet-4-...`) |
| `time_created` | integer | no | — | Creation timestamp (ms) |
| `time_updated` | integer | no | — | Last update timestamp (ms) |
| `time_compacting` | integer | yes | — | When compaction last ran (ms) |
| `time_archived` | integer | yes | — | Archive timestamp (ms); NULL = active |
| `time_suspended` | integer | yes | — | Suspension timestamp (ms) |
| `resume_attempts` | integer | no | `0` | Number of resume attempts |
| `time_idle` | integer | yes | — | When session went idle (ms) |
| `time_viewed` | integer | yes | — | Last viewed timestamp (ms) |
| `idle_outcome` | text | yes | — | Outcome of idle handling |

**Indexes:**
- `session_v2_project_idx` on `project_id`
- `session_v2_workspace_idx` on `workspace_id`
- `session_v2_parent_idx` on `parent_id`
- `session_v2_time_suspended_idx` on `time_suspended` WHERE `time_suspended IS NOT NULL`

---

### `session_message`

Individual messages within a session (v2). Each message has a sequence number
per session.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique message identifier |
| `session_id` | text FK → `session_v2.id` | no | — | Parent session |
| `type` | text | no | — | Message type (e.g. `message`) |
| `seq` | integer | no | — | Sequence number within session |
| `time_created` | integer | no | — | Creation timestamp (ms) |
| `time_updated` | integer | no | — | Last update timestamp (ms) |
| `data` | text | no | — | JSON blob containing message content |

The `data` JSON for role-bearing messages typically includes:
- `role` — `user`, `assistant`, etc.
- `modelID` — model used (for assistant messages)
- `time.completed` — completion timestamp

**Indexes:**
- `session_message_session_seq_idx` UNIQUE on `(session_id, seq)`
- `session_message_session_type_seq_idx` on `(session_id, type, seq)`
- `session_message_session_time_created_id_idx` on `(session_id, time_created, id)`
- `session_message_time_created_idx` on `(time_created)`

---

### `session_inbox`

Inbox queue for pending events awaiting delivery to a session.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique inbox entry identifier |
| `session_id` | text FK → `session_v2.id` | no | — | Target session |
| `type` | text | no | — | Entry type |
| `payload` | text | no | — | JSON payload |
| `delivery` | text | no | — | Delivery channel/mechanism |
| `enqueued_seq` | integer | no | — | Sequence at enqueue time |
| `time_created` | integer | no | — | Creation timestamp (ms) |

**Indexes:**
- `session_inbox_session_delivery_seq_idx` on `(session_id, delivery, enqueued_seq)`
- `session_inbox_session_enqueued_seq_idx` UNIQUE on `(session_id, enqueued_seq)`

---

### `session_pending`

Pending operations on sessions (e.g. compaction).

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique pending entry identifier |
| `session_id` | text FK → `session_v2.id` | no | — | Target session |
| `type` | text | no | — | Pending operation type (e.g. `compaction`) |
| `data` | text | no | — | JSON operation data |
| `delivery` | text | yes | — | Delivery mechanism |
| `admitted_seq` | integer | no | — | Sequence at admission time |
| `time_created` | integer | no | — | Creation timestamp (ms) |

**Indexes:**
- `session_pending_session_delivery_seq_idx` on `(session_id, delivery, admitted_seq)`
- `session_pending_session_compaction_idx` UNIQUE on `(session_id)` WHERE `type = 'compaction'`
- `session_pending_session_admitted_seq_idx` UNIQUE on `(session_id, admitted_seq)`

---

### `event_sequence`

Tracks the sequence number per aggregate (event sourcing).

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `aggregate_id` | text PK | no | — | Aggregate identifier |
| `seq` | integer | no | — | Current sequence number |
| `owner_id` | text | yes | — | Owning entity ID |

---

### `event`

Event store for event-sourced aggregates.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique event identifier |
| `aggregate_id` | text FK → `event_sequence.aggregate_id` | no | — | Parent aggregate |
| `seq` | integer | no | — | Event sequence number |
| `type` | text | no | — | Event type |
| `data` | text | no | — | JSON event payload |
| `created` | integer | no | `0` | Creation timestamp (ms) |

**Indexes:**
- `event_aggregate_type_seq_idx` on `(aggregate_id, type, seq)`
- `event_aggregate_seq_idx` UNIQUE on `(aggregate_id, seq)`

---

### `permission`

Per-project permission rules for tool actions.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique permission identifier |
| `project_id` | text FK → `project.id` | no | — | Parent project |
| `action` | text | no | — | Action type (e.g. `allow`, `deny`) |
| `resource` | text | no | — | Resource pattern (e.g. `bash(npm:*)`) |
| `time_created` | integer | no | — | Creation timestamp (ms) |
| `time_updated` | integer | no | — | Last update timestamp (ms) |

**Indexes:**
- `permission_project_action_resource_idx` UNIQUE on `(project_id, action, resource)`

---

### `credential`

Stored credentials for integrations (API keys, tokens, etc.).

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique credential identifier |
| `integration_id` | text | yes | — | Integration this credential is for |
| `label` | text | no | — | Human-readable label |
| `value` | text | no | — | Credential value (token/key) |
| `connector_id` | text | yes | — | Connector identifier |
| `method_id` | text | yes | — | Auth method identifier |
| `active` | integer | yes | — | Whether credential is active (boolean) |
| `time_created` | integer | no | — | Creation timestamp (ms) |
| `time_updated` | integer | no | — | Last update timestamp (ms) |

---

### `account`

SSO / OAuth accounts for opencode server authentication.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique account identifier |
| `email` | text | no | — | Account email |
| `url` | text | no | — | Server URL |
| `access_token` | text | no | — | OAuth access token |
| `refresh_token` | text | no | — | OAuth refresh token |
| `token_expiry` | integer | yes | — | Token expiry timestamp (ms) |
| `time_created` | integer | no | — | Creation timestamp (ms) |
| `time_updated` | integer | no | — | Last update timestamp (ms) |

---

### `control_account`

Control-plane account credentials (for opencode cloud / sync).

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `email` | text PK part | no | — | Account email |
| `url` | text PK part | no | — | Server URL |
| `access_token` | text | no | — | OAuth access token |
| `refresh_token` | text | no | — | OAuth refresh token |
| `token_expiry` | integer | yes | — | Token expiry timestamp (ms) |
| `active` | integer | no | — | Whether this is the active control account |
| `time_created` | integer | no | — | Creation timestamp (ms) |
| `time_updated` | integer | no | — | Last update timestamp (ms) |

**Primary key:** composite `(email, url)`

---

### `account_state`

Tracks the currently active account and organization.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | integer PK | no | — | Row ID (singleton, typically `1`) |
| `active_account_id` | text FK → `account.id` | yes | — | Currently active account |
| `active_org_id` | text | yes | — | Currently active organization |

---

### `project_directory`

Maps projects to additional working directories.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `project_id` | text PK part FK → `project.id` | no | — | Parent project |
| `directory` | text PK part | no | — | Directory path |
| `type` | text | yes | — | Directory type |
| `strategy` | text | yes | — | Linking strategy |
| `time_created` | integer | no | — | Creation timestamp (ms) |

**Primary key:** composite `(project_id, directory)`

---

### `worktree`

Maps projects to Git worktrees.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `project_id` | text PK part FK → `project.id` | no | — | Parent project |
| `directory` | text PK part | no | — | Worktree directory path |
| `strategy` | text | yes | — | Worktree strategy |
| `time_created` | integer | no | — | Creation timestamp (ms) |

**Primary key:** composite `(project_id, directory)`

---

### `workspace`

Represents a remote or local workspace environment.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Unique workspace identifier |
| `provider` | text | no | — | Workspace provider (e.g. `daytona`) |
| `binding` | text | yes | — | Binding identifier |
| `created_at` | integer | no | — | Creation timestamp (ms) |
| `last_used_at` | integer | no | — | Last used timestamp (ms) |

---

### `instruction_blob`

Stores instruction text blobs, deduplicated by hash.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `hash` | text PK | no | — | Content hash |
| `value` | text | yes | — | Instruction text content |

---

### `instruction_entry`

Per-session instruction key-value entries.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `session_id` | text PK part FK → `session_v2.id` | no | — | Parent session |
| `key` | text PK part | no | — | Instruction key |
| `value` | text | yes | — | Instruction value |
| `removed` | integer | no | `false` | Whether instruction was removed |
| `time_created` | integer | no | — | Creation timestamp (ms) |
| `time_updated` | integer | no | — | Last update timestamp (ms) |

**Primary key:** composite `(session_id, key)`

---

### `instruction_state`

Snapshot of instruction state per session (for incremental recomputation).

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `session_id` | text PK FK → `session_v2.id` | no | — | Parent session |
| `epoch_start` | integer | no | — | Epoch start sequence |
| `through_seq` | integer | no | — | Sequence processed through |
| `initial_values` | text | no | — | JSON of initial instruction values |
| `current_values` | text | no | — | JSON of current instruction values |

---

### `kv`

Generic key-value store for app state.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `key` | text PK | no | — | Unique key |
| `value` | text | no | — | JSON or raw value |
| `time_created` | integer | no | — | Creation timestamp (ms) |
| `time_updated` | integer | no | — | Last update timestamp (ms) |

---

### `migration`

Tracks schema migrations applied to the database.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | text PK | no | — | Migration identifier |
| `time_completed` | integer | no | — | Completion timestamp (ms) |

---

### `__drizzle_migrations`

Internal Drizzle ORM migration tracking table.

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | SERIAL PK | no | — | Auto-increment ID |
| `hash` | text | no | — | Migration hash |
| `created_at` | numeric | yes | — | Creation timestamp |
| `name` | text | yes | — | Migration name |
| `applied_at` | text | yes | — | Application timestamp (ISO string) |

---

### `sqlite_stat1`

SQLite internal statistics table (auto-maintained by ANALYZE). Contains query
planner statistics. Not application data.

---

## Entity Relationship Summary

```
project 1───* session_v2
project 1───* permission
project 1───* project_directory
project 1───* worktree

session_v2 1───* session_message
session_v2 1───* session_inbox
session_v2 1───* session_pending
session_v2 1───* instruction_entry
session_v2 1───1 instruction_state
session_v2 *───1 session_v2  (parent_id, self-referencing)
session_v2 *───1 workspace

event_sequence 1───* event

account 1───1 account_state
```

## Key Query Patterns

The following queries are used by the `opencode-sessions` scripts in `lib/db.sh`:

1. **Session listing** — Joins `session_v2` with `project`, filtering on
   `time_archived IS NULL` and `parent_id IS NULL` for top-level active sessions.

2. **Project listing** — Groups `project` joined to `session_v2` to count
   sessions per project.

3. **Running questions** — Queries `session_message` and inspects JSON `data`
   for tool parts with `state.status = 'running'`.

4. **Error detection** — Queries `session_message` for tool parts with
   `state.status = 'error'`.

5. **Child sessions** — Counts non-archived `session_v2` rows grouped by
   `parent_id`.

6. **Model extraction** — Reads `session_v2.model` JSON column and extracts
   `$.id` (e.g. `big-pickle` from `{"id":"big-pickle","providerID":"opencode"}`).

## v1 → v2 Migration Reference

The codebase was migrated from the v1 schema (`session`, `message`, `part`
tables) to the v2 schema (`session_v2`, `session_message`; no `part` table).

| v1 | v2 | Notes |
|---|---|---|
| `session` | `session_v2` | Renamed |
| `message` | `session_message` | Renamed |
| `part` table | gone | Parts embedded in `session_message.data` JSON `content` array |
| `json_extract(data, '$.role')` | `session_message.type` column | Direct column |
| `json_extract(data, '$.modelID')` | `json_extract(session_v2.model, '$.id')` | JSON object on session |
| `json_extract(p.data, '$.type') = 'tool'` | `json_each(data, '$.content')` → `$.type = 'tool'` | Via `json_each` |
| `json_extract(p.data, '$.tool')` | `json_extract(value, '$.name')` | Field renamed |
| `json_extract(p.data, '$.state.status')` | `json_extract(value, '$.state.status')` | Via `json_each` |
| `json_extract(p.data, '$.text')` (text) | `json_extract(value, '$.text')` via `json_each` | Assistant messages |
| `json_extract(p.data, '$.text')` (text) | `json_extract(data, '$.text')` | User/system/synthetic (flat) |

## Notes

- The database is managed by Drizzle ORM (see `__drizzle_migrations`).
- JSON columns (`data`, `metadata`, `sandboxes`, `commands`, `summary_diffs`,
  `initial_values`, `current_values`) are stored as text and parsed at the
  application layer.
- The `event` / `event_sequence` tables support an event-sourcing pattern for
  certain aggregates.
- Timestamps are in **Unix epoch milliseconds** throughout.
