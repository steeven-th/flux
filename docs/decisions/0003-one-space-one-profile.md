# 3. One space, one profile

Status: Proposed, to be validated by the first prototype

## Context

The main reason for Flux is to keep work, personal and client browsing apart without opening
several browser windows or apps. Each space needs its own cookies and logins, history, saved
passwords, extensions and site settings.

In Chrome style, a CEF request context created with its own `cache_path` under the root cache
directory maps to a Chromium profile. A profile already isolates cookies, storage, cache, saved
passwords, extensions and site permissions.

## Decision

Each new space gets its own Chromium profile by default. Several spaces can share a profile when
the user chooses to, but isolation is the default and the UI always shows which profile a space
uses.

Data that Flux keeps itself (sidebar tree, history used by the command bar, downloads list) is
stored per profile as well, so nothing from one profile shows up in another.

## Alternatives considered

- **Profiles as a separate concept that spaces opt into.** This is the model Arc used. It is
  flexible, but isolation becomes an extra step that many users never take.
- **Shared profile with partitioned cookies only.** Cheaper in memory, but history, passwords and
  extensions would still be shared.

## Consequences

- Each loaded profile has its own memory and disk footprint. Profiles of spaces that are not open
  should load lazily.
- Extensions are installed per profile. The UI needs a way to install an extension in several
  spaces at once.
- Deleting a space with its own profile deletes that profile's data, which needs a clear
  confirmation.
