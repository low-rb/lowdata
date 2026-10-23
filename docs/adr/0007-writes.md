# ADR 0007: Writing with `<<`, `<=`, `[]=` and `delete`

- **Status:** Accepted
- **Date:** 2026-10-22

## Context

Data expressions only read. An expression has `to_a`, `sql` and `dataset`, so a repository that inserts, updates or deletes rows drops out of the syntax and into Sequel:

```ruby
class PostsData < LowData
  def all = Posts[:title] + Users[:username]
  def create(post) = Posts.dataset.insert(post) # Not LowData
end
```

Writes should read like the rest of LowData: round brackets choose rows, square brackets choose columns, and operators do the work. A destructive write should also be obvious to anyone reading the code, including people who don't know LowData.

## Decision

| Operation | Syntax | SQL | Returns |
|---|---|---|---|
| Insert | `Posts << { title: 'Hello' }` | `INSERT` | the new row |
| Upsert | `Posts(slug: 'hello') <= { title: 'Hello' }` | `INSERT ... ON CONFLICT ... DO UPDATE` | the row |
| Update | `Posts(id: 1)[:title] = 'New'` | `UPDATE ... WHERE` | the assigned values |
| Delete | `Posts(id: 1).delete` | `DELETE ... WHERE` | the number of rows deleted |

One way to do each action:

- **`<<` adds rows.** It's Ruby's append, from `Array#<<`, `String#<<` and `IO#<<`.
- **`<=` adds rows or makes existing ones equal.** `<` puts the row in, and `=` makes a matching row equal to it.
- **`[]=` changes existing rows**, and never creates them. It's Ruby's assignment.
- **`delete` removes rows.** It's spelled out because a delete can't be undone, so it should be recognisable at a glance, and easy to grep for. Ruby's `Array` pairs `<<` with `delete` the same way.

Writes run immediately, as `Array#<<` does, rather than building an expression that runs on `to_a`. A repository method such as `def create(post) = Posts << post` does what it says.

`Table` stands for the repository's table in writes too, so `Table << post` inserts into `posts` in `PostsData`.

### Insert: `<<`

```ruby
Posts << { title: 'Hello', user_id: 1 }
# INSERT INTO posts (title, user_id) VALUES ('Hello', 1) RETURNING id
# => { id: 7 }

Posts[:id, :created_at] << { title: 'Hello', user_id: 1 }
# INSERT INTO posts (title, user_id) VALUES ('Hello', 1) RETURNING id, created_at
# => { id: 7, created_at: 2026-10-22 ... }

Posts << [{ title: 'Hello' }, { title: 'World' }]
# INSERT INTO posts (title) VALUES ('Hello'), ('World') RETURNING id
# => [{ id: 7 }, { id: 8 }]
```

- **Returns** the new row as a hash, or an array of hashes for an array of rows, as reads do. Square brackets choose its columns, and a bare table returns the primary key.
- **On MySQL**, which has no `RETURNING`, LowData reads the columns back by the new primary key.
- **Round brackets on an insert** raise, because there are no existing rows to choose. `Posts(slug: 'hello') << row` is almost certainly an upsert or update written with the wrong operator.

### Upsert: `<=`

Round brackets name the columns a row is matched on. Their values are written too, so the filter and the row together make the full row:

```ruby
Posts(slug: 'hello') <= { title: 'Hello' }
# INSERT INTO posts (slug, title) VALUES ('hello', 'Hello')
#   ON CONFLICT (slug) DO UPDATE SET title = excluded.title RETURNING id
# => { id: 7 }

Posts <= { id: 7, title: 'Hello' }
# ... ON CONFLICT (id) DO UPDATE SET title = excluded.title RETURNING id
```

- **Matching:** the round brackets' keys are the conflict target. Without round brackets, the primary key is, and the row must include it. Postgres and SQLite need a unique index on the target columns, and raise without one.
- **Filters:** only plain values, as in `Posts(slug: 'hello')`. A range, a block or a related table can't name a single row to match, so it raises.
- **Returns** the row, as insert does, with square brackets after the round ones choosing its columns: `Posts(slug: 'hello')[:id, :created_at] <= row`.
- **On MySQL**, `ON DUPLICATE KEY UPDATE` matches on any unique key rather than the named columns. LowData raises unless the named columns are the table's only unique key, so the match is the one written.

### Update: `[]=`

```ruby
Posts(id: 1)[:title] = 'New'
# UPDATE posts SET title = 'New' WHERE (posts.id = 1)

Posts(id: 1)[:title, :body] = ['New', '...']
# UPDATE posts SET title = 'New', body = '...' WHERE (posts.id = 1)

Posts(published: false) { created_at < cutoff }[] = { archived: true }
# UPDATE posts SET archived = TRUE WHERE ((posts.published = FALSE) AND (posts.created_at < '2026-01-01'))

Users(~Posts)[:active] = false
# UPDATE users SET active = FALSE WHERE NOT (EXISTS (SELECT 1 FROM posts WHERE (posts.user_id = users.id)))
```

- **Filters:** any round-bracket filter, including blocks and related tables, so update chooses rows exactly as a read does.
- **Returns** the assigned value. Ruby makes an assignment evaluate to its right-hand side whatever `[]=` returns, so the number of rows updated isn't available from the operator. `Posts(id: 1)[:title] = 'New'` evaluates to `'New'`.
- **Empty brackets with a hash:** `[] = { ... }` sets the hash's columns. If [ADR 0006](0006-bare-tables-and-empty-brackets.md) is accepted, `Posts[]` selects no columns in a read, and here the hash names them, so the two don't conflict.

### Delete: `delete`

```ruby
Posts(id: 1).delete
# DELETE FROM posts WHERE (posts.id = 1)
# => 1

Posts(published: false) { created_at < cutoff }.delete
# DELETE FROM posts WHERE ((posts.published = FALSE) AND (posts.created_at < '2026-01-01'))
# => 12
```

- **Filters:** any round-bracket filter, including blocks and related tables, as in update.
- **Returns** the number of rows deleted, as SQL, Sequel and most ORMs do.
- **Only on a table:** `Posts(id: 1)[:title].delete` raises, because square brackets choose columns and a delete removes whole rows.

### No filter, no write

An update or delete without round brackets would change every row in the table. Both raise instead:

```ruby
Posts[:archived] = true # Raises: "Choose the posts to update with round brackets, e.g. Posts(id: 1)[:archived] = true"
Posts.delete            # Raises: "Choose the posts to delete with round brackets, e.g. Posts(id: 1).delete"
```

Changing every row stays possible through `dataset`, so it's always deliberate.

### Where the writes are defined

- **`Writer`** runs every write, and **`WriteChecks`** checks a write before it runs.
- **`TableReference`** gets `<<`, `<=`, `[]=` and `delete`.
- **`DataExpression`** gets `<<` and `<=` for a single table in square brackets, which choose the columns returned, from its `Writes` module. Writing through a join, a nested expression or a sorted expression raises.
- **`<<` and the `expressions` gem:** from 0.4, `Expression#<<` calls its `append_*` hook on the expression itself and returns what the hook returns. `DataExpression` implements `append_value` to insert and return the rows, and raises from `append_expression` and `append_type`.
- **`<=` and the `expressions` gem:** `Expression#<=` builds: it calls its `lt_or_eq_*` hook on a copy and returns the copy, as the gem's other comparison operators do. An upsert has to run immediately and return the rows, so `DataExpression` overrides `<=` itself rather than using the hooks. The gem keeps `<=` as a building operator, because it reads as a comparison for most expression types. The override raises for anything but a hash or an array of hashes, so `Posts[:id] <= Users[:id]` can't be mistaken for a comparison or a join.

## Options considered

### Upsert: `<<` on a filtered table

`Posts(slug: 'hello') << row`, reading "add this to the post whose slug is hello".

- ✅ No Ruby warning or RuboCop autocorrect risk (see Consequences).
- ✅ One operator for every way of adding rows.
- ❌ Only the round brackets tell an insert from an upsert, which is easy to miss when reading.
- **Outcome:** rejected. Upsert gets its own operator, so the action is visible.

### Update: `<=`

`Posts(id: 1) <= { title: 'New' }`, reading "make post 1 equal to this".

- ✅ Can return the number of rows updated.
- ❌ Leaves upsert without an operator.
- **Outcome:** rejected in favour of `[]=`, which reads as assignment and can't be confused with an insert.

### Update: `<<` on a filtered table

- ✅ A forgotten filter inserts a row rather than updating every row.
- ❌ Brackets alone decide between insert and update.
- **Outcome:** rejected.

### Delete: assigning `nil`

`Posts(id: 1)[] = nil`, pairing with update.

- ❌ Clever rather than obvious, and it can't return a count.
- **Outcome:** rejected.

### Delete: unary minus

`-Posts(id: 1)`.

- ❌ Ruby warns `possibly useless use of -@ in void context`, which is where deletes usually are, and RuboCop's `Lint/Void` flags it.
- ❌ `-Col[:views]` already means descending.
- **Outcome:** rejected.

### Delete: `>>`

`Posts >> Posts(id: 1)`, the mirror of `<<`.

- ✅ Every write is an operator.
- ✅ No void-context warning, and it can return a count.
- ❌ Doesn't say "delete" to anyone who hasn't read LowData's docs, for the one write that can't be undone.
- ❌ One character from `>`, a right join. Under [ADR 0006](0006-bare-tables-and-empty-brackets.md), `Posts > Posts(id: 1)` would be a valid expression.
- ❌ Hard to grep for every place an app deletes data.
- ❌ The filter sits on the right, rather than the round brackets choosing rows as everywhere else.
- **Outcome:** rejected in favour of `delete`. Adding rows is safe to write tersely, and removing them isn't.

### Lazy writes

Writes could build an expression that runs on a method call, so `sql` could show it first.

- ✅ Previewing a write, and composing it before running it.
- ❌ `Posts << post` doing nothing until another call is a silent failure, and nothing else in Ruby's `<<` works that way.
- **Outcome:** rejected. Previewing a write's SQL is left open (see Out of scope).

### Square brackets as an input filter

`Posts[:title, :body] << params` writing only title and body from `params`, as Rails' `permit` and Sequel's `update_fields` do.

- ✅ One meaning for square brackets: the columns that go in and come out.
- ❌ Output and input usually differ. The generated `id` should come out, but `params` should never set it, so one list can't serve both. Prisma (`data` and `select`), Rails (`permit` and `returning:`) and SQL (`INSERT INTO posts (...)` and `RETURNING`) keep them separate for this reason.
- **Outcome:** rejected. Square brackets choose what comes out, the value is what goes in, and `params.slice(:title, :body)` filters it. Update is the exception, because `Posts(id: 1)[:title] = 'New'` names the column it sets and returns nothing. A hash assigned to one column raises rather than being filtered by the brackets.

## Out of scope

- **Nested writes:** inserting a user with their posts, e.g. `Users << { username: 'alice', posts: [...] }`.
- **Writes through joins**, such as updating posts by their user's columns. Related-table filters (`Posts(user: Users(username: 'alice'))[:title] = ...`) cover most of this already.
- **Previewing a write's SQL** without running it.
- **Updating with expressions**, such as `views = views + 1`.
- **Records:** writing a mutable, model-like object instead of a hash, e.g. `Posts(id: 1)[] = post`. Ruby makes an assignment return its right-hand side, so `[]=` can't return the updated rows, but it could fill the object in from `RETURNING`, setting `post.updated_at` as ActiveRecord's `save` does. Insert and upsert could fill in `id` and timestamps the same way. Open questions: a mutable record type, since `Data` objects are immutable; what to do when the round brackets choose more than one row; which columns to fill in; and reading back on MySQL.
- **Transactions.**

## Consequences

- **Ruby's void-context warning:** under `ruby -w`, a `<=` whose result is unused warns `possibly useless use of <= in void context`. Plain `ruby` is silent, and so is `<=` on a method's last line or in an assignment, which is the usual place for a repository's upsert. The warning has no category to turn off, so the README shows how to filter it with `Warning.ignore` from the `warning` gem. `<<`, `[]=` and `delete` don't warn.
- **RuboCop autocorrect deletes the upsert:** `Lint/Void` flags a mid-method `Posts(...) <= row` as autocorrectable, and `rubocop -A` turns it into a bare `Posts(...)`, silently removing the write. `Lint/Void` has no per-operator setting, so LowData ships a RuboCop config for apps to `inherit_gem`, `config/rubocop.yml`, that disables it. The README's upsert section says so first.
- **RuboCop autocorrect reverses the upsert:** `Style/YodaCondition` reads `Tags <= row` as a comparison with the constant first, and `rubocop -A` rewrites it to `row >= Tags`, which no longer upserts. The same config disables it.
- **Return values differ:** insert and upsert return rows, delete returns a count, and update returns the assigned values, because of Ruby's assignment rule.
- **Databases differ:** `RETURNING` (Postgres, SQLite 3.35+) is emulated on MySQL by reading back, and MySQL's upsert is limited to tables where the named columns are the only unique key.
- **Writes mix operators and a method:** adding and changing rows use operators, and deleting uses `delete`. The README explains why, so the exception reads as deliberate.
- `TableReference` and `DataExpression` gain write operators, `TableReference` gains `delete`, and the README gains a Writes section.
