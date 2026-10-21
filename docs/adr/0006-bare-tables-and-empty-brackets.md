# ADR 0006: Bare tables select every column, and empty brackets select none

- **Status:** Proposed
- **Date:** 2026-10-21

## Context

A table's square brackets choose its columns, and empty brackets choose every column:

```ruby
Posts[:title]   # SELECT posts.title FROM posts
Posts[]         # SELECT posts.* FROM posts
```

There's no way to select no columns from a table. That matters most for a junction table in a [nested join](../../README.md#nesting-joins). To nest each post's tags, the join has to go through `post_tags`, and `PostTags[]` pulls in every one of its columns:

```ruby
Posts[:title, tags: PostTags[] & Tags[:name]]
# => [{ title: 'Hello', tags: [{ id: 1, post_id: 1, tag_id: 1, created_at: ..., name: 'ruby' }] }]
```

What's wanted is `tags: [{ name: 'ruby' }]`. The same applies to a flat join that only uses a table to link or filter rows, such as `Users[] & Posts[:title]` returning only titles.

A bare table such as `Posts`, with no brackets, is a `TableReference`: a table waiting for its columns. It can be filtered (`Posts(published: true)`), negated (`~Posts`), and used in another table's round brackets (`Users(Posts)`), but it isn't a data expression:

| Expression | Today |
|---|---|
| `def all = Posts` | Returns the `TableReference`. `to_a` and `sql` raise `NoMethodError` |
| `Users + Posts` | `NoMethodError: undefined method '+'` |
| `Users[:username] + Posts` | `ArgumentError: Join a data expression such as Posts[:title], not the value #<LowData::TableReference ...>` |
| `Users[:username, Posts]` | `ArgumentError: Columns are symbols, e.g. Posts[:title], not #<LowData::TableReference ...>` |

## Decision (proposed)

A bare table selects every column, and empty brackets select none:

| Expression | Columns | SQL |
|---|---|---|
| `Posts` | every column | `SELECT posts.* FROM posts` |
| `Posts[:title]` | the ones listed | `SELECT posts.title FROM posts` |
| `Posts[]` | none | – |

```ruby
Posts[:title, tags: PostTags[] & Tags[:name]]
# => [{ title: 'Hello', tags: [{ name: 'ruby' }, { name: 'sql' }] }]

Users[] & Posts[:title]
# SELECT posts.title FROM users INNER JOIN posts ON (posts.user_id = users.id)

Users[:username] + Posts
# => [{ username: 'alice', posts: [{ id: 1, user_id: 1, title: 'Hello', ... }] }]
```

### A bare table is a data expression

`TableReference` behaves as the table with every column wherever a data expression is expected:

- **Operators:** `Posts + Users`, `Users & Posts`, `Posts ^ Col[:views]`, `Posts * 10` and the rest work as they do on `Posts[...]`.
- **On the right of an operator:** `DataExpression`'s hooks convert a `TableReference` before joining or nesting, so `Users[:username] + Posts` works.
- **In square brackets:** `Users[:username, Posts]` and `Users[:username, written: Posts]` nest every column of posts.
- **As a result:** `to_a` and `sql` work, so `def all = Posts` returns every post.
- **With filters:** `Posts(published: true)` already returns a `TableReference`, so `Posts(published: true)` on its own is every column of published posts.

Round brackets keep their meaning. `Users(Posts)` still keeps users with related posts, and `~Posts` is still only a filter.

### Empty brackets select no columns

- **In a flat join:** the table links and filters rows but adds no columns.
- **Nested:** each nested row is an empty hash, so `Users[:username, Posts[]]` gives `posts: [{}, {}]`. That's consistent, and it shows how many related rows there are. In a nested join, the other tables' columns fill each row.
- **On its own, or as the first table:** `Posts[]` alone, or `Posts[] + Users[:username]`, would select nothing from the subject, which isn't valid SQL in a flat query and is meaningless as the subject of nesting. It raises, suggesting `Posts` for every column.
- **Linking columns:** the columns nesting needs to link rows (such as `posts.id`) are still selected, and removed from the output as now.

### `Table`

`Table[...]` infers its joins from the columns it's given, so:

- **Bare `Table`** raises, since there are no columns to infer from. It doesn't mean every column of the repository's table, because `Posts` already does that.
- **`Table[]`** raises, as it would select nothing.

## Options considered

### `Posts[:*]` for every column, `Posts[]` for none

`:*` is a valid Ruby symbol and reads like SQL's `*`.

- ✅ Only square brackets choose columns, so the bare table keeps its current role.
- ❌ A special symbol to learn, where a bare table needs nothing.
- ❌ `:*` looks like a column named `*`.
- **Outcome:** rejected in favour of bare tables, which give the three cases (all, some, none) without new syntax.

### `Posts[*]` for every column

- ❌ Not valid Ruby in most methods: `[*]` forwards the method's anonymous rest argument, so a method without `*` in its parameters raises `SyntaxError: no anonymous rest parameter`.
- ❌ Worse in a method that takes `*`: `def search(*) = PostTags[*]` silently passes the method's own arguments in as columns.
- **Outcome:** rejected.

### Keep `Posts[]` for every column, and add a way to select none

For example `Posts[nil]`, or a method such as `Posts.none`.

- ✅ Not a breaking change.
- ❌ The empty case, which reads as "nothing", would keep meaning "everything", and selecting nothing would need the odder syntax.
- **Outcome:** rejected. LowData is at v0.1.0, so the clearer syntax is worth the break now.

## Consequences

- **Breaking change:** every `X[]` meaning "every column" becomes `X`. That's 8 in the README (such as `Likes[]` and `(Users[] < Posts[]) & Comments[]`), plus the fixtures and specs. Needs a changelog entry.
- **A typo risk:** `Users[Posts]` nests every column of posts under each user, and `Users(Posts)` keeps users that have posts. Only the bracket type differs, and both are valid, so a typo returns differently shaped data instead of raising. Round brackets already mean filtering everywhere, so the rule is consistent.
- **The junction table gap closes:** many-to-many nesting through a junction table returns only the columns asked for.
- `TableReference` gains the operators, `to_a` and `sql`, by converting itself to a data expression. `DataExpression`'s operator hooks and bracket arguments accept a `TableReference`.
- The comment in `TableReference#[]` and the README's examples change to the new meaning.
