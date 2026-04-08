---
date: 2026-04-08T03:05:50+03:00
git_commit: 976ef3924e34111f43bac8ecbb2e747a909ad03e
branch: main
repository: opencode-multiplexer
topic: "SQLite query optimization and time-based filtering for opencode-sessions-fzf.sh"
tags: [research, sqlite, performance, query-optimization, bash, cli]
last_updated: 2026-04-08
---

## Ticket Synopsis

**Ticket:** DEBT-001  
**Type:** debt (performance optimization + feature)  
**Priority:** high

The SQL queries in `opencode-sessions-fzf.sh` are too slow (target: under 1 second). Additionally, there's no way to filter sessions by age, causing old sessions to clutter the interface.

### Requirements
- Query execution time under 1 second
- Configurable time filter (default: 14 days) via `--days=N` flag
- New `--all` flag to show all sessions (bypass time filter)
- Show count of filtered vs total sessions in UI
- Query optimization approach (not adding indexes)

---

## Summary

**Primary Finding:** The current query uses multiple CTEs with correlated subqueries that execute per-row, causing slow execution. The main bottleneck is the `latest_msg` CTE which performs a correlated subquery for each session to find the latest message.

**Root Cause:** The query has 4-5 CTEs that each contain correlated subqueries in their WHERE clauses. Specifically:
1. `latest_msg` CTE uses a correlated subquery to find MAX(time_created) per session
2. `has_running_question` and `has_error` CTEs reference `latest_msg` with additional correlated subqueries
3. Multiple `json_extract()` calls on the same columns throughout

**Key Data:**
- Current SQLite version: 3.52.0 (supports JSON1 extension and window functions)
- Main bottleneck: correlated subqueries in CTEs (lines 100-182 in opencode-sessions-fzf.sh)
- Target: under 1 second execution time

---

## Detailed Findings

### 1. Current Query Structure Analysis

**File:** `opencode-sessions-fzf.sh:100-182`

The query consists of 6 CTEs:
1. `latest_msg` - Correlated subquery to find latest message per session (lines 103-111)
2. `has_running_question` - References latest_msg with correlated subquery (lines 112-122)
3. `has_child_question` - Complex join with multiple JSON filters (lines 123-133)
4. `has_error` - References latest_msg with correlated subquery (lines 135-143)
5. `child_count` - Simple aggregation (lines 145-150)
6. `last_model` - Another correlated subquery for model (lines 151-162)

**Performance Issues:**
- The `latest_msg` CTE is referenced by multiple other CTEs, causing repeated execution
- Each CTE with a correlated subquery executes once per row in the outer query
- Multiple `json_extract()` calls on same data without caching

### 2. SQLite Optimization Patterns Found

Based on research, the following techniques apply:

#### a) Window Functions Instead of Correlated Subqueries

**Pattern for latest message:**
```sql
-- BEFORE (correlated subquery):
latest_msg AS (
    SELECT m1.session_id, m1.id,
           json_extract(m1.data, '$.role') as role,
           json_extract(m1.data, '$.time.completed') as completed
    FROM message m1
    WHERE m1.time_created = (
        SELECT MAX(m2.time_created) FROM message m2 WHERE m2.session_id = m1.session_id
    )
)

-- AFTER (window function):
latest_msg AS (
    SELECT session_id, id, role, completed
    FROM (
        SELECT m.session_id, m.id,
               json_extract(m.data, '$.role') as role,
               json_extract(m.data, '$.time.completed') as completed,
               ROW_NUMBER() OVER (PARTITION BY m.session_id ORDER BY m.time_created DESC) as rn
        FROM message m
    ) WHERE rn = 1
)
```

#### b) Single-Pass JSON Extraction

```sql
-- Extract JSON once, then reference fields:
WITH parsed AS (
    SELECT id,
           json_extract(data, '$') as full_json
    FROM message
),
extracted AS (
    SELECT id,
           full_json ->> '$.role' as role,
           full_json ->> '$.time.completed' as completed
    FROM parsed
)
```

#### c) CTE Materialization Hint

```sql
-- Force SQLite to materialize CTE (useful when CTE is referenced multiple times):
WITH cte AS MATERIALIZED (
    SELECT * FROM large_table
)
```

### 3. Time-Based Filtering Implementation

**SQLite date functions available:**
```sql
-- Filter sessions by time_updated in last N days:
WHERE s.time_updated >= datetime('now', '-14 days')

-- Using Unix timestamp (time_updated appears to be milliseconds):
WHERE s.time_updated >= (strftime('%s', 'now') - 14 * 86400) * 1000
```

**CLI Argument Pattern (already exists in script):**
```bash
# Around lines 35-74 in opencode-sessions-fzf.sh:
--days)
    DAYS="$2"
    shift 2
    ;;
--all)
    SHOW_ALL="1"
    shift
    ;;
```

---

## Architecture Insights

### Query Execution Flow

The current query performs:
1. Full scan of `message` table for each CTE that references it
2. Multiple correlated subqueries that execute per session row
3. JSON extraction on every row multiple times

### Recommended Optimization Strategy

1. **Replace correlated subqueries with window functions** - Use `ROW_NUMBER() OVER (PARTITION BY ...)` instead of `WHERE col = (SELECT MAX(...) ...)`
2. **Single-pass JSON extraction** - Extract JSON once per row, then reference extracted values
3. **Materialize shared CTEs** - Use `AS MATERIALIZED` for CTEs referenced multiple times
4. **Add time filter in WHERE clause** - Filter early to reduce rows processed

### Time Filter Implementation

- Default: 14 days (configurable via `--days=N`)
- Use `datetime('now', "-${DAYS} days")` for SQLite date calculation
- Add `--all` flag to bypass time filter
- Show "Showing X of Y sessions" in output

---

## Code References

- `opencode-sessions-fzf.sh:35-74` - Argument parsing (add new --days and --all flags here)
- `opencode-sessions-fzf.sh:100-182` - Current query_all_sessions function (optimization target)
- `opencode-sessions-fzf.sh:268-296` - build_session_data function (add count display)
- `opencode-sessions-fzf.sh:340-353` - run_list function (add filtered count output)
- `opencode-sessions-fzf.sh:357-542` - run_interactive function (add count in footer)

---

## Historical Context (from thoughts/)

- `thoughts/tickets/debt_sql_performance.md` - Original ticket with requirements
- No existing time-filter implementation found in codebase

---

## Related Research

No existing research documents found for this topic.

---

## Open Questions

1. **Schema verification:** Need to verify the exact format of `time_updated` column (Unix milliseconds vs ISO timestamp) to implement correct time filter
2. **Performance benchmark:** Need to measure current query time before optimization
3. **Alternative approach:** Consider using two queries (one for count, one for data) if single optimized query still too slow

---

## Recommended Next Steps

1. Run `EXPLAIN QUERY PLAN` on current query to identify exact bottlenecks
2. Verify time_updated format in database schema
3. Implement optimized query using window functions
4. Add --days and --all CLI flags
5. Test query performance target (under 1 second)
6. Add filtered/total count display in UI