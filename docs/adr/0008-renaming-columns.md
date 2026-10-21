# ADR 0008: Renaming columns with `name: :column`

- **Status:** Accepted
- **Date:** 2026-10-22

## Context

Rows come back as hashes keyed by column name, so a hash can only hold one value per name. When joined tables share a column name, all but one value is silently lost:

```ruby
Users[:id, :username] & Posts[:id, :title]
# SELECT users.id, users.username, posts.id, posts.title FROM users INNER JOIN posts ON (posts.user_id = users.id)
# => [{ id: 1, username: 'alice', title: 'Hello' }] # posts.id is gone
```

The same happens with `name`, `created_at` and every shared column of `Users[] & Posts[]`. Renaming keys in Ruby after loading can't fix this, because the value is lost before Ruby sees the row. There's no way to get both values today.

Renaming a column on a single table is mostly cosmetic. An app can rename keys after loading, or convert every key in its serializer. Renaming alone wouldn't justify new syntax, but the join collision does.

## Decision

A keyword with a symbol value renames a column. The key is the name the value is returned under, and the value is the column it comes from:

```ruby
Posts[:id, headline: :title]
# SELECT posts.id, posts.title AS headline FROM posts
# => [{ id: 1, headline: 'Hello' }]

Users[:username, user_id: :id] & Posts[:title, post_id: :id]
# SELECT users.username, users.id AS user_id, posts.title, posts.id AS post_id FROM users INNER JOIN posts ON (posts.user_id = users.id)
# => [{ username: 'alice', user_id: 1, title: 'Hello', post_id: 1 }]
```

### The key is what you get back

Keywords in square brackets already name nested tables, with the output key on the left:

```ruby
Reviews[:rating, author: Users[:username]]
# => [{ rating: 5, author: { username: 'alice' } }]
```

Renames follow the same rule, so square brackets have one rule for keywords: the key is what you get back, and the value is where it comes from. Later features fit the same slot, where the key has to be the output name because there's no source column to put there:

```ruby
Users[:username,
  handle: :login,              # a renamed column (this ADR)
  posts: Posts[:title],        # a nested table
  post_count: Count[Posts],    # an aggregate (not yet decided)
  age: Col[:born_on].age]      # a computed column (not yet decided)
```

### Where renames work

Everywhere a table's square brackets do:

| Expression | Renamed |
|---|---|
| `Posts[headline: :title]` | A table's own columns. A rename counts as a column, so this selects only `headline`. |
| `Users[:username] & Posts[headline: :title]` | Columns in a flat join |
| `Users[Posts[headline: :title], handle: :username]` | Columns of nested tables and their parents |
| `Users[:username] + (Posts[headline: :title] & Comments[:body])` | Columns in a nested join |
| `Table[:username, headline: :title]` | Columns in data inversion, from whichever related table owns them |

Nesting still selects the columns it links rows by, even when they're renamed, and drops them from the output as before. `Users[Posts[:title], handle: :username]` selects `users.id` to find each user's posts.

Ruby requires keyword arguments to come after positional ones, so renames go last in the brackets, with named nested tables: `Users[:id, Posts[:title], handle: :username]`. Writing a rename before a column or an unnamed nested table is a `SyntaxError`.

### Writing it backwards raises

`title: :headline` reads like SQL's `title AS headline`, and Ruby passes `:title => :headline` as the same keyword, so some renames will be written backwards. Two rules make every backwards rename raise:

- **The column must exist:** `Posts[title: :headline]` raises `posts has no headline column. To rename title, write headline: :title`.
- **The new name must not be a column of the table:** `Posts[title: :views]` raises `posts already has a title column, so views can't be renamed to it`.

The second rule also stops a rename from clashing with the columns nesting links rows by, such as `user_id`.

### Other errors

- **A name used twice:** `Posts[:views, views: :title]` raises.
- **A name used by a nested table:** `Posts[Users[:username], user: :title]` raises, because the nested user is returned as `user`.
- **Values that aren't symbols:** raise as now, suggesting round brackets for filters, so `Posts[views: 100..]` still points to `Posts(views: 100..)`.

### Sorting

`Col[]` names columns, not output names, so a renamed column sorts by its column: `Posts[headline: :title] ^ Col[:title]`. `Col[:headline]` raises `No table in posts has a headline column to sort by`.

## Options considered

### `title: :headline` (column first)

- ✅ Reads in the same order as SQL's `title AS headline`, and as Ruby's `Hash#transform_keys(title: :headline)`.
- ❌ The opposite of nested tables, where the key is the output name. A reader scanning for the keys they get back would see `title` and get `headline`.
- ❌ Doesn't extend to computed columns, which have no column to put on the left.
- **Outcome:** rejected. Writing it this way raises with the fix (see "Writing it backwards raises").

### `Col[:title].as(:headline)`

- ✅ Unambiguous, and what Sequel does.
- ❌ Verbose, and it leaves the keyword slot behind.
- **Outcome:** rejected.

### Renaming after loading

`.map { |row| row.transform_keys(title: :headline) }`.

- ✅ No new syntax.
- ❌ Can't fix join collisions, because the value is lost before Ruby sees the row.
- ❌ Painful for nested data.
- **Outcome:** rejected as the only answer, though it's still fine for cosmetic renames.

### Prefixing clashing columns automatically

`Users[] & Posts[]` returning `users_id` and `posts_id`.

- ✅ Fixes clashes nobody named.
- ❌ Renames columns nobody asked to rename, and changes existing results.
- **Outcome:** out of scope for this ADR. It could still be added for unnamed clashes, alongside renames.

## Out of scope

- **Computed columns** and **aggregates**, which would use the same keyword slot.
- **Raising, or prefixing, when joined tables return the same name** without a rename, as in `Users[:id] & Posts[:id]`.
- **Sorting by an output name**, as in `^ Col[:headline]`.

## Consequences

- Rows can include every column of a join, by renaming the ones that clash.
- `Source` and `Inversion` gain `renames`, a hash of output names to columns. `columns` is unchanged, so only the code that builds select lists, and the code that slices nested rows, needs to know about renames.
- A rename is checked against the database's columns when the query is built, so a backwards rename raises before any SQL runs.
- `Table[]` accepts keywords for the first time, but only renames.
- Renames always come last in square brackets, because of Ruby's argument order.
