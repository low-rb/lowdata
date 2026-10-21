# ADR 0005: Nesting with `Table[]`

- **Status:** Proposed
- **Date:** 2026-10-21

## Context

`Table[]` inverts the usual query: you name the columns you want, and LowData joins the repository's table to whichever related table owns each column. In `PostsData`:

```ruby
Table[:title, :username, :body]

# SELECT posts.title, users.username, comments.body FROM posts
#   LEFT JOIN users ON (posts.user_id = users.id)
#   LEFT JOIN comments ON (comments.post_id = posts.id)
# => [
#   { title: 'Hello', username: 'alice', body: 'Again' },
#   { title: 'Hello', username: 'alice', body: 'Nice' },
#   { title: 'World', username: 'alice', body: nil }
# ]
```

`Table[]` is LowData's most original idea, but it's narrow:

- **It only returns flat rows.** A column on the "many" side, such as `body` from `comments`, repeats each post once per comment. `Table[...] * 10` therefore limits joined rows, not posts, so it can return fewer than 10 posts.
- **It can't nest.** `Table[:title] + Comments[:body]` raises `Table[] can't be joined with other expressions`, and `Table[]` brackets take column names only.

Since [ADR 0001](0001-meaning-of-plus.md) and [ADR 0002](0002-bracket-nesting-and-filters.md), nesting has grown two features that `Table[]` could build on:

- **Nested joins:** `Users[:username] + (Posts[:title] & Comments[:body])` nests a join's rows under a table.
- **Tables under a join:** `(Users[:username] & Posts[:title]) + Comments[:body]` nests a table under each row of a join.

`Table[]` is a flat join (posts left joined to the tables that own its columns), so both features apply to it.

## Options

### Option 1: nest under `Table[]`

`Table[]` stays flat, and other tables can nest under it, with `+` or in its brackets:

```ruby
Table[:title, :username] + Comments[:body]
Table[:title, :username, Comments[:body]]

# SELECT posts.title, users.username, posts.id AS lowdata_posts_id FROM posts LEFT JOIN users ON (posts.user_id = users.id)
# SELECT body, post_id FROM comments WHERE (post_id IN (...))
# => [
#   { title: 'Hello', username: 'alice', comments: [{ body: 'Again' }, { body: 'Nice' }] },
#   { title: 'World', username: 'alice', comments: [] }
# ]
```

- **How:** `NestingTree` treats `Table[]` as a join, which `NestedJoin` already supports. A nested table links through whichever of the join's tables it has a foreign key to, as with any join.
- **Existing expressions:** unchanged. `Table[:title, :body]` still repeats posts.

- ✅ Small: it reuses tables under a join, with no new rules.
- ✅ Doesn't change any existing result.
- ✅ The nested table keeps everything a nested table can do: its own columns, filters, sorts, per-parent limits, names, and tables nested under it.
- ❌ Nesting is still written by hand, so `Table[]` only infers half the query: the flat half.
- ❌ A "many" side column in `Table[]` still repeats rows, and limits still count joined rows.
- ❌ Two ways to get comments: `Table[:title, :body]` (flat, repeating) and `Table[:title] + Comments[:body]` (nested).

### Option 2: infer nesting from the columns

`Table[]` decides what's flat and what's nested from the direction of each foreign key:

- **The repository's table, and tables it points to** (the "one" side): flat, as now. Each post has at most one user, so `username` can't repeat posts.
- **Tables pointing to the repository's table** (the "many" side): nested as an array named after the table, as `+` names them.

```ruby
Table[:title, :username, :body]

# SELECT posts.title, users.username, posts.id AS lowdata_posts_id FROM posts LEFT JOIN users ON (posts.user_id = users.id)
# SELECT body, post_id FROM comments WHERE (post_id IN (...))
# => [
#   { title: 'Hello', username: 'alice', comments: [{ body: 'Again' }, { body: 'Nice' }] },
#   { title: 'World', username: 'alice', comments: [] }
# ]
```

- **How:** `Inversion` splits the owners of the columns into the "one" side, which stays in the join, and the "many" side, which nests under it as tables under a join. Each "many" side table runs its own query.
- **Existing expressions:** any `Table[]` with a column on the "many" side changes from flat, repeating rows to nested arrays.

- ✅ The fullest form of inversion: you describe the output, and LowData works out the joins and the shape.
- ✅ Every post appears exactly once, as with `+`, so `Table[...] * 10` means ten posts.
- ✅ Covers the common case (a record with its parents' columns and its children) in one expression with no operators.
- ❌ A breaking change to `Table[]` results. LowData is at v0.1.0, so semantic versioning allows it, but it needs a changelog entry.
- ❌ The shape depends on the schema: the same list of columns gives flat or nested output depending on which way the foreign keys point.
- ❌ Only reaches tables directly related to the repository's table, as now. Comments' votes, two tables away, still need option 1 or brackets.
- ❌ `Table[]` can no longer return flat "many" side rows. Explicit joins such as `Posts[:title] < Comments[:body]` still can.
- ❌ More open questions: how to name a nested table whose name clashes with a column, and whether "many" side columns can be filtered or sorted from `Table()`.

### Option 3: both

Option 2 changes what `Table[]` infers, and option 1 lets tables nest under it, so they don't conflict. `Table[]` would infer the common case, and `+` or brackets would add anything it can't infer, such as a nested table with its own filter or sort, or a table further away:

```ruby
Table[:title, :username] + Comments(approved: true)[:body, Votes[:score]]
```

Option 1 is also a step towards option 2, because option 2 nests "many" side tables under the join in the same way.

### Option 4: leave `Table[]` as it is

- ✅ No work and no change.
- ❌ `Table[]` stays the one part of LowData that can't nest, while every other expression can.

## Comparison

| | Changes existing results | Rows repeat | Infers nesting | Size |
|---|---|---|---|---|
| 1. Nest under `Table[]` | no | yes, for "many" side columns | no | small |
| 2. Infer nesting | yes | no | yes | medium |
| 3. Both | yes | no | yes | medium |
| 4. Leave as is | no | yes | no | none |

## Decision

Not yet made.

## Consequences

To be written once an option is chosen. Either way:

- README's "Data Inversion" section needs updating, since it says `Table[]` returns one flat row per post.
- `Table[]` inside other expressions, as in `Users[:username, Table[...]]`, stays out of scope: `Table[]` stands for the repository's table, so it only makes sense as the subject.
