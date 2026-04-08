---
type: debt
priority: high
created: 2026-04-08T10:30:00Z
created_by: Opus
status: implemented
tags: [performance, sql, sqlite, query-optimization, filtering]
keywords: [sqlite3, CTE, json_extract, query-optimization, time-filter]
patterns: [subquery-optimization, json-query-optimization, sql-indexing]
---

# DEBT-001: Optimize SQL queries and add time-based filtering

## Description

The SQL queries in `opencode-sessions-fzf.sh` are too slow (target: under 1 second). Additionally, there's no way to filter sessions by age, causing old sessions to clutter the interface.

## Context

- Current SQLite version: 3.52.0 (modern, supports JSON1 extension)
- Query execution is too slow for interactive use
- Users want to focus on recent sessions (last 14 days by default)

## Requirements

### Functional Requirements

- Query execution time under 1 second
- Add configurable time filter (default: 14 days)
- New `--days=N` flag to set time window
- New `--all` flag to show all sessions (bypass time filter)
- Show count of filtered vs total sessions in UI

### Non-Functional Requirements

- Query optimization approach (not adding indexes)
- Maintain current functionality and output format
- Backward compatible with existing flags

## Current State

Complex CTE query with multiple correlated subqueries causing slow execution. No time filtering.

## Desired State

Optimized single-pass query with configurable time filtering.

## Research Context

### Keywords to Search

- sqlite3 CTE optimization - Understanding common table expression performance
- json_extract performance - JSON query optimization in SQLite
- correlated subquery - Why current subqueries are slow
- sqlite query planner - Understanding how SQLite optimizes queries

### Patterns to Investigate

- Current CTE structure - Multiple CTEs with correlated subqueries in WHERE clause
- JSON extraction patterns - Multiple json_extract calls on same columns
- Latest message lookup - Correlated subquery for latest message per session

### Key Decisions Made

- Query optimization approach (not indexes) - User preference
- Configurable time filter - Default 14 days, --days=N flag
- Show count when filtered - UI shows filtered/total count
- --all flag for no-filter - Shows all when no sessions in window

## Success Criteria

### Automated Verification

- [ ] Query completes in under 1 second (time sqlite3 query)
- [ ] --days flag correctly filters sessions
- [ ] --all flag bypasses time filter
- [ ] Output shows filtered/total count

### Manual Verification

- [ ] Interactive mode loads quickly
- [ ] List mode shows correct count
- [ ] Time filter works as expected
- [ ] All existing flags still work

## Related Information

- File: `opencode-sessions-fzf.sh`
- Current query function: `query_all_sessions()` (lines 100-182)

## Notes

Query optimization strategies to consider:
1. Use window functions instead of correlated subqueries
2. Combine multiple JSON extractions into single pass
3. Use indexed columns directly instead of JSON extraction in WHERE
4. Pre-compute derived values
5. Consider materialized CTEs where appropriate