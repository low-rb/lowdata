# ADR 0001: What `+` means in a data expression

- **Status:** Accepted
- **Date:** 2026-10-20

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

**`+` is a many-to-one join (option 6).** It keeps every row of the subject exactly once, as a left join, and adds columns from the tables those rows point to.

- **Subject:** the rows come from the one table in the expression that no other table points to.
- **Joins:** every other table is left joined by following foreign keys up from the subject, so each subject row appears exactly once.
- **Order:** the order you write the tables in doesn't matter.
- **When it raises:** when two tables point to the same table (`Posts + Comments + Likes`), when tables aren't linked by a foreign key, or when more than one foreign key links two tables.

```ruby
Users[:username] + Posts[:title]                    # every post once, with its username
Comments[:body] + Posts[:title] + Users[:username]  # every comment once, with post title and username
Users[:username] + Posts[:title] + Comments[:body]  # same rows
```

For "posts with their comments", where rows repeat, use `<` or `Table[]` instead.

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

### Option 5: nested results

`+` keeps one row per row of the first table. A related table your rows point to is merged into the row; related rows that point back at yours are attached as arrays.

```ruby
Posts[:title] + Users[:username] + Comments[:body]
# => [{ title: 'Hello', username: 'alice', comments: [{ body: 'Nice' }] }, ...]
```

- ✅ No repeated or mixed rows, and `LIMIT 10` means ten subjects.
- ✅ Matches what applications render. PostgREST's resource embedding is the closest prior art.
- ✅ Gives `+` a job no other operator does.
- ❌ Two result shapes: `+` returns nested hashes while the other operators return flat rows.
- ❌ Hardest to build: one query per table, or database-specific JSON functions.
- ❌ Order matters, and you can't filter or sort on nested columns as easily as on a flat join.

### Option 6: many-to-one join (chosen)

Described under [Decision](#decision).

- ✅ Order doesn't matter, so `+` behaves like arithmetic.
- ✅ No repeated, dropped or mixed rows: one flat row per subject row.
- ✅ Covers the most common application query: child rows with their parents' columns.
- ✅ The README example works as written.
- ✅ Not a copy of `<`: `+` is the constrained join, and the other operators are unconstrained.
- ✅ Extensible: anything it refuses raises, so `+` can later return results for those cases (for example nested results) without breaking anyone.
- ❌ It refuses "posts with their comments", so people have to learn that `+` only joins towards the "one" side.
- ❌ The schema picks the subject. That's acceptable because exactly one table can qualify, and it raises otherwise.

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
| 5. Nested results | yes | no | no | no | ❌ |
| **6. Many-to-one join** | **no** | **no** | **no** | **no** | **✅** |
| 7. Undefined | – | – | – | – | ✅ |

## Naming

The option was first called a "lookup join". It's documented as a **many-to-one join**:

- "Many-to-one" consistently means this relationship elsewhere: ORM relationships (`@ManyToOne`, Django's `ForeignKey`), pandas `merge(validate="many_to_one")`, which raises when rows would repeat, and Looker's `relationship: many_to_one`.
- "Lookup" is more familiar (Excel's `VLOOKUP`, ETL lookup steps, Flink's Lookup Join) but overloaded: MongoDB's `$lookup` nests the "many" side as arrays, and Django's "lookups" are filters.
- Cardinality doesn't say which join type, so the docs state that rows are kept as a left join, and that "many-to-one" is from the subject's side (many posts to one user), whatever order the tables are written in.

The code keeps `lookup` as its internal name (`:lookup`, `LowData::Lookup`).

## Consequences

- `+` is the everyday join for "rows with their context", and `&`, `<`, `>` and `<=>` give explicit control.
- `+` runs are compiled as a group: the generated SQL starts `FROM` the subject, whatever order the tables are written in. Columns are still selected in the order they were written.
- `+` must come before other joins in an expression, e.g. `(Users[] + Posts[]) < Comments[]`. A `+` that follows another join raises.
- If "posts with their comments" through `+` turns out to be needed, nested results (option 5) can be added for the cases that raise today without breaking existing queries.
