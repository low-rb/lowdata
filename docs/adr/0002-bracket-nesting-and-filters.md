# ADR 0002: Nesting, naming and filtering inside brackets

- **Status:** Accepted. Filters are superseded by [ADR 0003](0003-round-bracket-filters.md)
- **Date:** 2026-10-20

## Context

[ADR 0001](0001-meaning-of-plus.md) made `+` nest related rows: the first table is the subject, and each other table nests under whichever table its foreign key links it to. That leaves three gaps:

1. **Which table does it nest under?** In `Users + Posts + Likes`, `likes` points to both `users` and `posts`, so `+` can't tell whether likes belong under each user or each post, and raises.
2. **Which foreign key does it use?** `reviews` has `author_id` and `editor_id`, both pointing to `users`, so `Reviews + Users` raises. The same table can't appear twice either, so a review's author and editor can't both be nested.
3. **No filters.** There's no way to write a `WHERE` clause in a data expression.

Gaps 1 and 2 are different problems. Gap 1 is about the *structure* of the expression, and gap 2 is about *naming* a link.

## Decision

Tables already take their columns in brackets: `Posts[:title]`. Brackets also take nested tables, names and filters, and Ruby picks the meaning from each argument's type, in the same way the `expressions` gem picks a hook:

| Argument | Meaning | Example |
|---|---|---|
| Symbol | column | `Posts[:title]` |
| Data expression | nested table | `Users[:username, Posts[:title]]` |
| Keyword with a data expression | nested table under that name, which also picks the foreign key | `Reviews[:rating, author: Users[:username]]` |
| Keyword with any other value | filter | `Posts[:title, published: true]` |

### Structure

A table in brackets nests directly under the table whose brackets it's in:

```ruby
Users[:username, Posts[:title, Likes[]]]
# => [{ username: 'alice', posts: [{ title: 'Hello', likes: [{ id: 1, ... }] }] }]
```

The code has the shape of the output, as with GraphQL and PostgREST's `select=username,posts(title,likes(*))`.

`+` stays as shorthand where the structure can be inferred: `Posts[:title] + Users[:username]` returns the same data as `Posts[:title, Users[:username]]`. Parentheses group a `+` chain, so `Users + (Posts + Likes)` nests likes under posts. Each operand of `+` can be a bracketed table, and a bracketed table can contain a `+` chain.

### Naming

A keyword names the nested key:

```ruby
Reviews[:rating, author: Users[:username], editor: Users[:username]]
# => [{ rating: 5, author: { username: 'alice' }, editor: { username: 'bob' } }]
```

When the nested table is on the "one" side, the name also picks the foreign key: `author` follows `reviews.author_id`. That's also how the same table can appear twice. On the "many" side the name only renames the key, so two foreign keys pointing back (e.g. reviews written versus reviews edited by a user) still raise.

Without a name, keys default as in ADR 0001: the foreign key column without `_id` for the "one" side, and the table name for the "many" side.

### Filters

Filters use Ruby's own value types, like ActiveRecord's and Sequel's hash conditions:

```ruby
Posts[:title, published: true]           # WHERE published = TRUE
Posts[:title, views: 100..]              # WHERE views >= 100
Posts[:title, views: ...10]              # WHERE views < 10
Posts[:title, status: %w[draft live]]    # WHERE status IN ('draft', 'live')
Posts[:title, deleted_at: nil]           # WHERE deleted_at IS NULL
```

- **In nested data,** a filter applies to the table it's written on. On a nested table it filters the nested rows, not the parents: `Users[:username, Posts[:title, published: true]]` returns every user, each with only their published posts.
- **In flat SQL joins** (`&`, `<`, `>`, `<=>`), every filter goes in the `WHERE` clause and applies to the joined rows, as in SQL. Filtering the optional side of a left join therefore removes rows without a match.
- **`Table[]`** takes column names only.

### Ruby's argument order

Ruby requires positional arguments before keyword arguments. Columns and unnamed nested tables come first, then named nested tables and filters in any order:

```ruby
Posts[:title, Likes[], user: Users[:username], published: true]   # valid
Posts[:title, published: true, Likes[]]                           # SyntaxError
```

## Options considered

### Structure

**Parentheses only (`Users + (Posts + Likes)`).**
- ✅ Reuses `+` with no new syntax.
- ❌ Long expressions need nested parentheses, and they can't name a link.
- **Outcome:** supported as a grouping for `+`, but not the main way to nest.

**Brackets (chosen).**
- ✅ The code has the shape of the output, and there are no precedence problems.
- ✅ Keywords give names and filters a place in the same syntax.
- ❌ Ruby's argument order (positional before keyword) has to be learned.

**Methods (`Users[:username].nest(Posts[:title])`).**
- ✅ Explicit.
- ❌ Wordier than brackets, and it moves the structure out of the data expression into method calls.

### Naming

**Keywords (chosen).** The nested key and the foreign key are named in one place.

**Methods (`Users[:username].as(:author)` or `.via(:author_id)`).**
- ❌ More words for the same thing, and they separate the name from where the table is nested.

### Filters

**Comparison operators (`Posts[:views] > 100`).** The `expressions` gem calls different hooks for a value than for an expression, so `>` could filter for a value and right join for an expression.
- ❌ The same operator would mean a join or a filter depending on the right-hand side.
- ❌ `==` can't be overloaded safely, so equality, the most common filter, would need different syntax.
- **Outcome:** rejected.

**Keywords with Ruby values (chosen).**
- ✅ Familiar from ActiveRecord and Sequel, and Sequel already turns ranges, arrays and `nil` into the right SQL.
- ✅ Shares the bracket syntax with nesting, told apart by the value's type.
- ❌ Only covers `AND`ed equality, ranges, `IN` and `IS NULL`.

**A block or method passed to Sequel (`.where { views > 100 }`).** Deferred, see below.

## Out of scope

- **Complex filters:** `OR`, comparing columns, and SQL functions. A `.where { ... }` method passing a block to Sequel is the likely shape.
- **Sorting and limits,** including sorted or limited nested rows. Sorting would be cheap, since each nested table has its own query. Limits per parent ("each user's 5 latest posts") need window functions or lateral joins.
- **Filtering parents by their children** ("users who have published posts"), as PostgREST does with `!inner`.
- **Naming which foreign key to follow on the "many" side.**

## Consequences

- Nesting, naming and simple filtering share one syntax, and `+` stays as shorthand where it can infer the structure.
- Two keyword arguments can't share a name, so a filter and a nested table can't both be called `user`. Columns and nested keys can still clash in the output, e.g. a `user` column and a nested `user:`. LowData doesn't check for that yet.
- Bracketed nested tables are still loaded with one query per table, and each table's filters go in its own query.
