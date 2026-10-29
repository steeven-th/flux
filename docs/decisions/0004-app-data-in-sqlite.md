# 4. App data in SQLite

Status: Proposed

## Context

Chromium stores its own data in each profile folder (cookies, passwords, extensions). Flux keeps
data that Chromium doesn't expose through CEF: spaces, the sidebar tree (folders, pinned tabs,
favorites), open tabs, archived tabs and the downloads list. Browsing history is Chromium's own,
see [ADR 6](0006-history-read-from-chromium.md).

Archives grow over time and need fast text search. The sidebar tree changes on every
drag and drop.

## Decision

Use SQLite through GRDB.swift.

- One app database for global data: spaces, profiles, window state, preferences.
- One database per profile, stored in the Chromium profile folder, for the sidebar tree, tabs and
  downloads. Removing a profile removes its folder and nothing is left behind.
- Full text search with FTS5 for the archive.
- Sibling order in the sidebar uses fractional indexing, so a move updates one row.

## Alternatives considered

- **JSON files.** Simple to start with, but every change rewrites the whole file, there is no
  search, and a crash during a write can corrupt the file.
- **Core Data or SwiftData.** Tied to Apple's object graph, harder to inspect and migrate, and no
  direct access to FTS5.
- **Raw SQLite C API.** No dependency, but GRDB gives migrations, observation and type-safe records
  for little cost.

## Consequences

- One third-party dependency (GRDB, MIT).
- Schema changes go through versioned migrations from the start.
