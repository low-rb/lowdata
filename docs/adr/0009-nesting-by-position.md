# ADR 0009: `+` nests by position, and joins link to the table before them

- **Status:** Accepted
- **Date:** 2026-10-22
- **Supersedes:** [ADR 0001](0001-meaning-of-plus.md)'s rule for where each table nests. Its other decisions stand: `+` nests, the first table is the subject, the "one" side nests as an object and the "many" side as an array, and each table runs one query.

## Context

Under ADR 0001, the first table in a `+` chain is the subject, and every other table nests under whichever table its foreign key links it to, wherever it's written:

```ruby
Users + Posts + Comments  # comments link to posts, so they nest in posts
Posts + Comments + Likes  # comments and likes both link to posts, so they nest side by side
Users + Comments + Posts  # the same as Users + Posts + Comments
```

Flat joins work the same way: each table in `Users & Posts & Comments` joins to whichever table already joined it has a foreign key to.

LowData never guesses: when foreign keys allow more than one shape, it raises. Two problems remain.

### The shape isn't in the code

`Users + Posts + Comments` is a chain and `Posts + Comments + Likes` is two siblings, and nothing in the text says which. A reader needs the schema to know what an expression returns, which matters most for people who didn't write it: reviewers, newcomers, and the author months later.

### Foreign keys between other tables break queries

Every table's position depends on its links to every other table in the expression, so a foreign key that the query never meant to use can break it:

- **A migration breaks production without a code change.** LowData reads foreign keys from the live database, and most teams migrate before deploying. When another team adds a foreign key, queries nobody touched start raising "more than one path".
- **The person who added the key doesn't own the query,** and the person who owns the query didn't change anything. Tests catch it only if that exact query is covered.
- **The README's headline case already has the problem in most real schemas.** Comments usually have a `user_id` for their author, so `Users + Posts + Comments` is ambiguous from the start. Likes, reactions, notifications and audit logs are similar: tables linking users and something else are everywhere.
- **Flat joins are affected too.** With `comments.user_id`, `Users & Posts & Comments` raises "More than one foreign key links comments to users, posts".

## Decision: `+`

### A path, with siblings in an array

`+` nests the table after it in the table before it. Siblings go in an array:

```ruby
Users + Posts + Comments              # comments in posts, in users
Posts + [Comments, Likes]             # comments and likes side by side, in posts
Users + [Posts + Comments, Orders]    # in each user: posts with their comments, and orders
Users + Posts + [Comments, Likes]     # in each user: posts, each with comments and likes
```

- **The subject** is still the first table, and each of its rows appears exactly once.
- **`+` is associative.** `Users + (Posts + Comments)` and `(Users + Posts) + Comments` both nest comments in posts in users. Parentheses are only needed around a nested join, because `&` binds less tightly than `+`, and around a sort or limit for one table (see "Sorts and limits").
- **An array nests its elements in the table before it.** Each element can be a table, a path or a join, so the expression has the shape of the result.
- **Order matters**, because it is the structure. `Users + Comments + Posts` nests posts in comments, and raises if comments don't link to posts that way.

### Foreign keys link adjacent tables only

Foreign keys decide how two adjacent tables link, as before: a table the rows point to nests as an object named after the foreign key (`user:`), and a table pointing to the rows nests as an array named after the table (`posts:`). Only the foreign keys between those two tables are considered:

```ruby
Users + Posts + Comments
# comments link to posts by comments.post_id. comments.user_id is ignored: comments are next to posts, not users.
```

So a foreign key between tables that aren't adjacent can never break an expression or change its shape. The "more than one path" error goes away. The only remaining case is more than one foreign key between the same two tables, such as `reviews.author_id` and `reviews.editor_id`, which raises as now and is resolved by naming one (`author:`) or naming the column (`Reviews(:author_id)`).

### A named foreign key reaches further back

A foreign key named in round brackets links a table to the table that key points to, instead of the table before it. It reaches back to any earlier table in the same path:

```ruby
Users + Posts + Comments + Orders(:user_id)
# orders.user_id points to users, so orders nest in users, beside posts
# the same as Users + [Posts + Comments, Orders]

Users + Posts + Orders(:user_id) + LineItems
# line items nest in orders, the table before them, so the path continues from orders
```

- **Nothing is inferred.** The column says which table it points to, so a new foreign key can't change where the table goes.
- **Only earlier tables in the same path.** A key pointing to a sibling, or to a table outside the path, raises: `orders.user_id points to users, which isn't earlier in this path`.
- **Only the "many" side.** The key has to be on the table being placed. A table that an earlier table points to, such as nesting a comment's author under the comment rather than under its post, is written as a sibling instead: `Comments + [Posts, Users]`.
- **One meaning everywhere.** A named foreign key already chooses between two keys linking the same pair (`Reviews(:author_id)`) and the table a nested join links through (`Likes(:user_id)`). In each case it says the same thing: link this table by this key.

Arrays stay the main way to write siblings, because the shape is visible at a glance. Reach-back suits a single table that belongs further up, and matches how flat joins reach back (see below).

### Names

Arrays hold unnamed children only. A nested table that needs a name other than its table's, such as `tags:` for a join through `post_tags`, uses inline nesting: `Posts[:title, tags: PostTags[:created_at] & Tags[:name]]`.

### Nested joins

A join written next to `+` links through the table written next to the `+`:

```ruby
Users + (Posts & Likes)      # links through posts, the first table of the join
(Users & Posts) + Comments   # links through posts, the last table of the join
```

Today both of these raise when more than one of the join's tables links ("posts and likes both link to users"). By position, they don't. Naming the foreign key, `Likes(:user_id)`, is still possible to link through a table that isn't next to the `+`.

### Sorts and limits

Unchanged. A sort after a path sorts the subject, and a sort or limit on one table applies per parent:

```ruby
Users[:username] + (Posts[:title] ^ -Col[:views] * 3) ^ Col[:username]
Users[:username] + [Posts[:title] ^ -Col[:views] * 3, Orders[:total]] ^ Col[:username]
```

Commas end each array element, so a sort or limit inside an array applies to its own element without parentheses.

### Square brackets

Inline nesting, `Posts[:title, Comments[:body], Likes[]]`, stays. It means the same as `Posts[:title] + [Comments[:body], Likes[]]`: both nest children in that table. `+` is the readable default, and brackets suit short expressions that keep a table's columns and children together.

### Errors

An unlinked adjacent pair raises, and suggests both ways to link the table to an earlier one:

```ruby
Posts + Comments + Likes
# No foreign key links likes to comments. To nest likes in posts, beside comments, write
# Posts + [Comments, Likes] or Posts + Comments + Likes(:post_id)
```

## Decision: joins

### Each join links to the table before it

In a chain of `&`, `<`, `>` and `<=>`, each table joins to the table written before it, using only the foreign keys between those two tables:

```ruby
Users[:username] & Posts[:title] & Comments[:body]
# SELECT ... FROM users INNER JOIN posts ON (posts.user_id = users.id) INNER JOIN comments ON (comments.post_id = posts.id)
# comments.user_id is ignored, so adding it can't break the query
```

### A named foreign key reaches further back

Joins often fan out from one table. Two spokes can be reordered so that each pair is adjacent (`Posts & Users & Orders`), but three or more can't. A foreign key column says which table it points to, so naming it joins to that table wherever it is in the chain:

```ruby
Posts[:title] & Users[:username] & Orders[:total] & Addresses(:user_id)[:city]
# addresses join to users, because addresses.user_id points to users
```

It's the same `Table(:column)` syntax as for `+`, so `+` and joins follow one rule: link to the table before, or name a foreign key to reach further back. An unnamed table with no foreign key to the table before it raises, and the error suggests the foreign key to name:

```ruby
Users & Posts & Orders
# No foreign key links orders to posts. Join orders to users by naming its foreign key: Orders(:user_id)
```

### Not a fallback to the nearest table

Joining to the nearest earlier table that links would handle fans without syntax, but a new foreign key between adjacent tables would then silently reroute an existing join instead of raising. Every rule in this ADR either uses the table written next to an operator or a foreign key the query names, so no new foreign key can silently change a query.

`Table[]` is unaffected: it joins the repository's table directly to the table that owns each column.

## Options considered

### Keep ADR 0001's rule

- ✅ Siblings need no syntax, and order doesn't matter after the first table.
- ❌ The shape isn't in the code.
- ❌ Foreign keys between other tables break queries, including in common schemas from the start.
- **Outcome:** replaced.

### Named arrays

`Posts[:title] + [Comments, tags: PostTags & Tags]`, where keywords in the array name children.

- ✅ Naming without square brackets.
- ❌ A second way to do what inline nesting already does.
- **Outcome:** rejected. Inline nesting names children.

### Sibling syntax: `|`

`Posts + (Comments | Likes)`.

- ✅ An operator, and `+` binds tighter than `|`, so paths need no parentheses inside a group.
- ❌ A group always needs parentheses, or `Posts + Comments | Likes` puts likes beside posts.
- ❌ `|` has the same precedence as `^`, so `(Comments | Likes ^ Col[:id])` sorts the whole group.
- ❌ `|` already means `OR` in filter blocks.
- **Outcome:** rejected in favour of arrays.

### Sibling syntax: a hash

`Posts + { comments: Comments, likes: Likes }`.

- ✅ Names every child.
- ❌ Every child needs a name, even when its table's name would do, and inline nesting already names children.
- **Outcome:** rejected.

### Sibling syntax: square brackets only

`Users[:username] + Posts[:title, Comments[:body], Likes[]]`.

- ✅ No new syntax.
- ❌ Brings back nested brackets, mixing columns and children in one list.
- **Outcome:** kept as an alternative, not the only way.

### Sibling syntax: unary `-` to step back

`Users + Posts + Comments + -Reviews`.

- ❌ Cryptic, `-` already means descending on `Col`, and it gets Ruby's void-context warning in some positions.
- **Outcome:** rejected.

### Nearest linked table, for `+` and joins

Each table links to the nearest earlier table it has a foreign key to.

- ✅ Siblings and fans need no syntax.
- ❌ A new foreign key between nearer tables silently changes the shape or the join.
- **Outcome:** rejected.

## Comparison with ADR 0001's options

ADR 0001's criteria, with two more: whether the shape can be read without the schema, and whether a foreign key the query doesn't use can break it.

| Option | Order matters | Rows repeat | Rows drop | Mixed rows | Shape in code | Unrelated keys break it |
|---|---|---|---|---|---|---|
| Full outer join | no | yes | no | yes | flat | yes |
| Natural join | no | yes | yes, without raising | no | flat | yes: any shared column |
| 1. Relationship join | no | yes | yes | no | flat | yes |
| 2. Remember the table to keep | yes | yes | no | no | flat | yes |
| 3. Keep every table with a foreign key | no | yes | no | yes | flat | yes |
| 4. Repository's table | no | yes | no | no | flat | yes |
| Left join from the first operand | yes | yes | no | no | flat | yes |
| 5. Nested results (ADR 0001) | first table only | no | no | no | no | yes |
| 6. Many-to-one join | no | no | no | no | flat | yes |
| 7. Undefined | – | – | – | – | – | – |
| **Nested by position (this ADR)** | **yes** | **no** | **no** | **no** | **yes** | **only a second key between adjacent tables** |

This keeps every guarantee that chose option 5, and is the only option that does well on the two new criteria. Its regression is order, which ADR 0001 counted as a plus and option 5 had already given up for the first table.

## Out of scope

- Whether inline nesting should eventually be removed in favour of `+ [...]`.
- Sibling joins in a flat chain other than by naming foreign keys.

## Consequences

- **Breaking changes:**
  - Siblings: `Posts + Comments + Likes` becomes `Posts + [Comments, Likes]`.
  - Grouping: `Users + (Posts + Likes)` can be written `Users + Posts + Likes`. Parentheses are no longer needed.
  - Order: `Users + Comments + Posts` raises, and has to be written `Users + Posts + Comments`.
  - Joins: fan-shaped chains such as `Users & Posts & Orders` need reordering or a named foreign key.
- **Errors removed:** "more than one path" for `+`, and "both link to" for nested joins written next to `+`.
- **Robustness:** a new foreign key can only break an expression if it's a second key between two tables written next to each other, and then it raises. No new foreign key can silently change a result.
- **Two ways to write siblings:** an array, or a named foreign key reaching back. The README leads with arrays.
- **Code:** `NestingTree` builds the tree from the expression's structure instead of searching foreign keys between every pair, and `QueryCompiler` joins each table to the one before it. Both get simpler.
- **README:** Flat nesting describes paths and arrays. The `Users + (Posts + Likes)` explanation, and the paragraph on order, are replaced.
- **ADR 0001** is marked as superseded in its rule for where tables nest.
