# ADR 0001: What `+` means in a data expression

- **Status:** Accepted. Where each table nests is superseded by [ADR 0009](0009-nesting-by-position.md): each table nests in the one before it, not wherever its foreign key leads.
- **Date:** 2026-10-20
- **Revised:** 2026-10-20. The decision was first option 6 (a flat many-to-one join), then changed to option 5 (nested results) with the subject taken from operand order. See [Why option 6 was replaced](#why-option-6-was-replaced).

## Context

LowData joins tables with operators, taking each `ON` clause from the database's foreign keys. Four operators have clear meanings:

| Operator | Join |
|---|---|
| `&` | Inner join |
| `<` | Left join |
| `>` | Right join |
| `<=>` | Full outer join |

`+` is the operator people will reach for first, and the README's headline example uses it:

```ruby
class PostsData < LowData
  def all
    Users[:username] + Posts[:title, :body]
  end
end
```

The README promises "a list of posts with the user's username included in each row". `+` has to deliver that, and it also has to behave predictably in chains such as `Users + Posts + Comments`.

The examples below use this data:

```
users:    1 alice, 2 bob, 3 carol
posts:    Hello (user 1), World (user 2), Orphan (no user)
comments: Nice (on Hello)
```

Every option was judged on these questions:

- **Order:** does writing the tables in a different order change the rows?
- **Repeats:** can adding a table repeat rows?
- **Drops:** can adding a table remove rows you already had?
- **Mixed rows:** do all result rows represent the same kind of thing?
- **Extensible:** can the meaning be widened after release without a breaking change?

## Decision

**`+` nests related rows (option 5), with the first table as the subject and both directions nested.**

- **Subject:** the first table written. Each of its rows appears exactly once.
- **The "one" side:** a table the rows point to is nested as an object, named after the foreign key (`posts.user_id` nests as `user:`).
- **The "many" side:** a table pointing to the rows is nested as an array, named after the table (`posts: [...]`).
- **Order:** only the first table's position matters. Each other table nests under the table its foreign key links it to, whatever order it's written in.
- **Queries:** one query per table, filtered with `IN (...)` on the parent rows' keys, so there are no N+1 queries. `+` has no single SQL query, so `sql` and `dataset` raise and `to_a` returns the nested data.
- **When it raises:** when foreign keys link the tables by more than one path, when a table isn't linked, when more than one foreign key links two tables, or when `+` is combined with `&`, `<`, `>`, `<=>` or `Table[]`.

```ruby
Posts[:title] + Users[:username]
# => [{ title: 'Hello', user: { username: 'alice' } }, { title: 'Orphan', user: nil }, ...]

Users[:username] + Posts[:title] + Comments[:body]
# => [{ username: 'alice', posts: [{ title: 'Hello', comments: [{ body: 'Nice' }] }] }, { username: 'carol', posts: [] }, ...]
```

The README's headline example becomes `Posts[:title, :body] + Users[:username]`: posts, each with its user nested.

## Options considered

### Full outer join (the first implementation)

`+` keeps every row from both sides.

- ✅ Order doesn't matter, and it's the literal "add everything together" reading.
- ❌ The most visible operator does the rarest join in application code.
- ❌ The README example becomes wrong: users without posts also appear.
- ❌ MySQL doesn't support it.
- **Outcome:** moved to `<=>`, which reads as "both directions" next to `<` and `>`.

### Natural join on shared column names (as in Axiom)

`+` matches rows on every column the tables have in common.

- ✅ Precedent: Axiom uses `+` for a natural join.
- ❌ In real schemas it gives wrong results without raising: `users` and `posts` share `id`, `created_at` and `updated_at`, so it joins on all three and usually returns nothing.
- **Outcome:** rejected. Foreign keys are where the schema actually records how tables relate.

### Option 1: relationship join

Each `+` keeps every row of whichever table holds the foreign key between its two operands.

- ✅ Each `+` can be read on its own, and order doesn't matter.
- ✅ Simple to build: each step looks at two tables.
- ❌ Chains drop rows. `Users + Posts + Comments` keeps only posts that have comments, because the last step keeps comments.
- ❌ The rows you get come from the schema (the table furthest down the foreign keys), not from your intent.
- ❌ Not extensible: it returns rows for every chain, so changing them later breaks users.

### Option 2: chains remember the table to keep

The first table holding a foreign key becomes the table to keep, and later `+` joins left join onto it.

- ✅ `Users + Posts + Comments` returns every post.
- ❌ Order matters: `Comments + Posts + Users` keeps comments instead.
- ❌ The same `+ Comments` means different joins in different expressions, so you have to trace the whole chain to read one step.
- ❌ Moving part of a chain into its own method can change the rows.

### Option 3: keep every table with a foreign key

`+` never drops a row from any table holding a foreign key. `+` runs are compiled as a group, using `FULL JOIN` between such tables when a foreign key is nullable.

- ✅ Order doesn't matter, and joins between two tables are unchanged.
- ❌ Mixed rows: asking for "comments with post and author" also returns rows for posts without comments.
- ❌ It's right for only one of three common query shapes (posts with everything). It returns extra rows for comments with context and drops users for users with everything.
- ❌ The most complex to build, and it needs `FULL JOIN`.

### Option 4: always keep the repository's table

In `PostsData`, `+` always keeps every post.

- ✅ Order doesn't matter, and every row is a post.
- ❌ The same expression returns different rows in different repositories.
- ❌ It duplicates `Table[]`, which already keeps the repository's table.

### Left join from the first operand

`+` is a left join: start with the first table you write and add the rest.

- ✅ The simplest rule of all, and it reads left to right ("users with their posts and comments").
- ✅ Never drops rows, and it covers all three query shapes if you write the subject first.
- ❌ It's the same as `<`, so two operators would do one job.
- ❌ Order matters: `Users + Posts` and `Posts + Users` return different rows, which weakens "joins as arithmetic".
- ❌ Rows repeat when you join a table on the "many" side.
- ❌ Not extensible.

### Option 5: nested results (chosen)

Described under [Decision](#decision). As first proposed, the "one" side was merged into the row (`{ title:, username: }`) rather than nested. Nesting both directions was chosen instead:

| | Merged "one" side | Nested "one" side (chosen) |
|---|---|---|
| `Posts + Users` | `{ title:, username: }` | `{ title:, user: { username: } }` |
| Column name clashes, e.g. two `id`s | possible | impossible |
| Matches Rails' `post.user.username` | no | yes |
| Shape depends on relationship direction | yes | no: always nested |

- ✅ No repeated, dropped or mixed rows, and `LIMIT 10` means ten subjects.
- ✅ Reads in written order: `Users + Posts + Comments` is users with their posts and comments.
- ✅ Covers every common query shape: child rows with context (`Comments + Posts + Users`), parents with children (`Posts + Comments`) and everything from the top (`Users + Posts + Comments`).
- ✅ Matches how Ruby developers use related data (`user.posts`, Rails `includes`) and the tools they use: Prisma `include`, GraphQL, Hasura, PostgREST's resource embedding and EdgeQL shapes all nest along relationships.
- ✅ Gives `+` a job no other operator does: `+` builds data structures, and the other operators are SQL joins.
- ❌ Two result shapes: `+` returns nested hashes while the other operators return flat rows, and `+` can't be combined with them.
- ❌ Order matters, so `+` isn't commutative. Ruby developers don't expect it to be: `"a" + "b"` and `[1] + [2]` aren't either.
- ❌ More to build: one query per table, then grouping in Ruby.
- ❌ No single SQL query, and you can't filter or sort on nested columns as simply as on a flat join.

### Option 6: many-to-one join (first chosen, then replaced)

`+` only adds columns from the tables your rows point to. The subject is the one table in the expression that no other table points to, every other table is left joined by following foreign keys up from it, and the result is one flat row per subject row.

```ruby
Users[:username] + Posts[:title]                    # every post once, with its username
Comments[:body] + Posts[:title] + Users[:username]  # every comment once, with post title and username
Users[:username] + Posts[:title] + Comments[:body]  # same rows
```

- ✅ Order doesn't matter, so `+` behaves like arithmetic.
- ✅ No repeated, dropped or mixed rows: one flat row per subject row.
- ✅ Covers the most common application query: child rows with their parents' columns.
- ✅ Not a copy of `<`: `+` is a left join that raises instead of repeating rows, as pandas' `merge(how="left", validate="many_to_one")` does.
- ❌ It refuses "posts with their comments", so people have to learn that `+` only joins towards the "one" side.
- ❌ The schema picks the subject, not the person writing the query.
- ❌ Only partly extensible: see below.

#### Why option 6 was replaced

Because option 6 infers the subject, both orders of a pair mean the same thing: `Posts + Comments` and `Comments + Posts` both return comments with their post. So `Posts + Comments` can never later mean "posts with their comments" without changing results people already rely on.

Tracking operand order was considered as a first step (the first table is the subject, and anything on the "many" side raises). With order tracked, `+` returns exactly the rows of a left join (`<`), and raises where `<` would repeat rows. That turned out to be the flat first stage of option 5: adding nesting only turns those errors into results. Rather than release the first stage and nest later, `+` implements option 5 fully now, while LowData is unreleased.

### Option 7: leave `+` undefined

`+` raises until real use shows what it should mean.

- ✅ Extensible, and avoids committing early.
- ❌ The README's headline example, and the "joins as arithmetic" pitch, has nothing behind it.

### Also ruled out

- **`UNION ALL`, as in Ruby's `Array#+`:** familiar to Ruby developers, but it isn't a join, so it changes LowData's pitch. `|` (`UNION`) and `-` (`EXCEPT`) remain available for set operations.
- **Semi-join** (users who have posts, without post columns): nothing about `+` suggests filtering.
- **Arithmetic on columns:** `Users[...]` selects a table's columns, not a value to add.
- **Inner join:** already `&`.

## Comparison

| Option | Order matters | Rows repeat | Rows drop | Mixed rows | Extensible |
|---|---|---|---|---|---|
| Full outer join | no | yes | no | yes | ❌ |
| Natural join | no | yes | yes, without raising | no | ❌ |
| 1. Relationship join | no | yes | yes | no | ❌ |
| 2. Remember the table to keep | yes | yes | no | no | ❌ |
| 3. Keep every table with a foreign key | no | yes | no | yes | ❌ |
| 4. Repository's table | no | yes | no | no | ❌ |
| Left join from the first operand | yes | yes | no | no | ❌ |
| **5. Nested results** | **first table only** | **no** | **no** | **no** | **–** |
| 6. Many-to-one join | no | no | no | no | partly |
| 7. Undefined | – | – | – | – | ✅ |

## Naming

While option 6 was the decision, `+` was documented as a **many-to-one join**, after first being called a "lookup join". "Many-to-one" consistently means that relationship elsewhere (ORM relationships, pandas `validate="many_to_one"`, Looker), while "lookup" is overloaded: MongoDB's `$lookup` nests the "many" side as arrays, and Django's "lookups" are filters.

With option 5, `+` is documented as **nesting**, the same idea as PostgREST's "resource embedding", Prisma's `include` and Rails' `includes`. "Many-to-one" still describes the "one" side, which nests as an object. The code uses `:nest` and `LowData::Nesting`.

## Consequences

- `+` is the way to load rows with their related data, and `&`, `<`, `>` and `<=>` are SQL joins returning flat rows.
- `+` returns nested hashes from `to_a`. `sql` and `dataset` raise, because `+` runs one query per table.
- `+` can't be mixed with the SQL join operators or `Table[]`. Flat results that keep every post with its comments use explicit joins: `(Users[] > Posts[]) < Comments[]`.
- Each nested key comes from the schema: the foreign key column without `_id` for the "one" side, and the table name for the "many" side. A table linked by two foreign keys, such as `reviews.author_id` and `reviews.editor_id`, raises for now. Naming each nested key after its foreign key column (`author:`, `editor:`) would be a later, compatible way to support it.
