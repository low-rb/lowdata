# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Minor features that don't break backwards compatibility are released as patches.

## Unreleased

### Changed

- A bare table, `Posts`, selects every column, and empty brackets, `Posts[]`, select none. Replace `Posts[]` with `Posts`

### Fixed

- Assigning a hash to one column, `Posts(id: 1)[:title] = { ... }`, raises instead of storing `0`

## 0.2.0

### Added

- Support nested joins, `Users[:username] + (Posts[:title] & Comments[:body])`
- Support tables nested under flat joins
- Column renaming: `Posts[:id, headline: :title]`
- Insert: `Posts << row`
- Upsert: `Posts(slug: 'hello') <= row`
- Update: `Posts(id: 1)[:title] = 'New'`
- Delete: `Posts(id: 1).delete`

### Changed

- Each table in a `+` chain nests in the table before it, rather than wherever its foreign key leads
- Operators return a new expression, so a named expression can be reused
