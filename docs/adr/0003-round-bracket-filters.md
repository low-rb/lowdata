# ADR 0003: Filters in round brackets

- **Status:** Accepted
- **Date:** 2026-10-21
- **Supersedes:** the Filters section of [ADR 0002](0002-bracket-nesting-and-filters.md)

## Context

ADR 0002 put filters inside a table's square brackets as keywords, next to its columns and nested tables: `Posts[:title, Likes[], views: 100..]`. That has three problems:

1. **Square brackets do everything.** Columns, nested tables, names and filters share one argument list, and each argument's type decides its meaning.
2. **Ruby's argument order.** Keywords must come after positional arguments, so `Posts[:title, published: true, Likes[]]` is a syntax error.
3. **Simple filters only.** Keyword filters cover `AND`ed equality, ranges, `IN` and `IS NULL`. There's no place for `OR`, column comparisons, SQL functions, or filtering rows by their related rows ("users who have published posts"), which ADR 0002 left out of scope.

## Decision

A table name followed by round brackets filters the table. Square brackets then only choose columns and nested tables:

```ruby
Posts(published: true) { (views > 100) | featured }[:title, Likes[], author: Users[:username]]
#     filters           conditions                 columns and nested tables
```

Each kind of bracket has one job, in the order a query runs: take posts, keep the matching rows, then choose what to return.

### Round brackets: filters

Keywords filter by Ruby values, as ADR 0002's filters did:

```ruby
Posts(published: true)                 # WHERE published = TRUE
Posts(views: 100..)                    # WHERE views >= 100
Posts(status: %w[draft live])          # WHERE status IN ('draft', 'live')
Posts(deleted_at: nil)                 # WHERE deleted_at IS NULL
```

Empty round brackets are allowed but not needed: `Posts()[:title]` is the same as `Posts[:title]`.

### Curly brackets: conditions

A block holds conditions that need more than a value. It's a Sequel virtual row block, so a bare name is a column:

```ruby
Posts { views > 100 }                  # WHERE views > 100
Posts { (views > 100) | (views < 10) } # OR
Posts { updated_at > created_at }      # comparing columns
Posts { lower(title) =~ 'hello' }      # SQL functions
```

- **Local variables work** (`Posts { views > minimum }`), but the block runs in Sequel's virtual row, so repository methods and instance variables don't. A block argument keeps `self`: `Posts { |post| post.views > minimum_views }`.
- **Use `&` and `|`, not `&&` and `||`.** Ruby can't overload `&&` and `||`, so `{ views > 100 && published }` silently becomes `{ published }`. LowData can't detect that, because `{ published }` is a valid condition on its own.
- **Columns are qualified with the block's table,** so a block's conditions stay on its own table in a flat join: `Users[:username] & Posts { views > 100 }[:title]` filters `posts.views`.
- Round brackets and a block can be combined: `Posts(published: true) { views > 100 }`. Their conditions are `AND`ed.

### Tables in round brackets: related rows

A table inside round brackets keeps the rows that have related rows in it, following the foreign key as nesting does:

```ruby
Users(Posts)[:username]                      # users with at least one post: WHERE EXISTS (...)
Users(Posts(published: true))[:username]     # users with a published post
Users(~Posts)[:username]                     # users with no posts: WHERE NOT EXISTS (...)
Users(~Posts(published: true))[:username]    # users with no published posts
Users(Posts => 3..)[:username]               # users with 3 or more posts: WHERE (SELECT count(*) ...) >= 3
Users(Posts(Likes))[:username]               # users with a post that has likes
Reviews(author: Users(username: 'alice'))[:rating]   # reviews whose author is alice
```

- **`~` means "has none".** Sequel already uses `~` for `NOT`.
- **A count** is a table as a key with a number or range as its value. `0` compiles to `NOT EXISTS`, `1..` to `EXISTS`, and anything else to a `count(*)` subquery.
- **"Every related row matches"** is "no related row fails to match": `Users(~Posts(published: false))`.
- **A name picks the foreign key** on the "one" side, as it does in nesting: `author:` follows `reviews.author_id`.

### Reusing a filtered table

A filtered table without square brackets is a value, so it can filter the parents and the nested rows from one place:

```ruby
published = Posts(published: true)
Users(published)[:username, published[:title]]
# Users with a published post, each with only their published posts
```

This covers PostgREST's `!inner`, and the filter is written once.

### `Table()`

Data inversion takes filters the same way, on the repository's table: `Table(published: true)[:username, :title]`.

### How table names become methods

`Posts(...)` is a method call, so LowData defines `method_missing` on repositories. It handles a capitalised name only when a table of that name exists in `LowData.database`, so a typo such as `Psots(...)` raises `NoMethodError`. The table list is cached, and setting `LowData.database` clears the cache. `Table(...)` always works, as `Table[...]` does.

## Options considered

**Keywords in square brackets (ADR 0002).**
- ✅ One syntax for everything.
- ❌ Mixes filters with columns and tables, and runs into Ruby's argument order.
- **Outcome:** replaced. Keywords in square brackets now only name nested tables, and any other keyword value raises with a pointer to round brackets.

**Hashes as operands (`Posts[:title] & { published: true }`).**
- ✅ `&` for `AND`, `|` for `OR` and `-` for `NOT` line up with SQL's precedence.
- ❌ `&` would mean a join or a filter depending on its right-hand side.

**Enumerable methods (`Posts[:title].select { views > 100 }`).**
- ❌ `select` means filtering in Ruby but choosing columns in SQL.

**Plain Ruby blocks parsed with Prism, so `&&` and `||` work.**
- ✅ The most natural syntax.
- ❌ It needs the block's source on disk and has to resolve its local variables, so it's fragile and a large piece of work.

**Prisma-style condition hashes (`where: { views: { gt: 100 } }`).**
- ❌ Explicit but verbose.

**Real methods defined per table when the database connects,** instead of `method_missing`.
- ❌ There's no single moment to define them: `LowData.database` can be set before or after repositories are loaded, and changed in tests. Checking the cached table list in `method_missing` behaves the same.

## Out of scope

- **Sorting and limits.** See ADR 0004.
- **`OR` across related tables** (users with a published post *or* who are admins). Inside a block `Posts(...)` would be read as an SQL function call, so it needs something like `exists(Posts(...))`.
- **Tables related to themselves** (`users.manager_id`), which need table aliases.
- **Naming the foreign key to follow on the "many" side,** as in ADR 0002.

## Consequences

- Square brackets only choose columns and nested tables, and every filter moves to round brackets.
- Filtering by related rows works in flat joins, nested data and `Table()`, using `EXISTS` and `count(*)` subqueries.
- Round brackets only work inside repository instance methods, where `method_missing` is defined. Constants such as `Posts[...]` still work anywhere `const_missing` does.
- Ruby continues a statement on the next line only while a bracket is open. Break lines inside the brackets and keep `) {` and `}[` together: a `[` at the start of a line starts a new array literal, silently dropping the columns.
