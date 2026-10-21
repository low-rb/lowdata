<a href="https://rubygems.org/gems/lowdata" title="Install gem"><img src="https://badge.fury.io/rb/lowdata.svg" alt="Gem version" height="18"></a>

## LowData

LowData follows the repository pattern with a twist; Data Expressions. Use simple arithmetic to evaluate expressions that represent database tables.

This expression combines the `posts` table with the `users` table while representing it conceptually as simple arithmetic:

```ruby
class PostsData < LowData
  def all
    Posts[:title, :body] + Users[:username]
  end
end
```

The above expression returns a list of posts with each post's user nested inside it:

```ruby
[
  { title: 'Hello', body: '...', user: { username: 'alice' } },
  { title: 'World', body: '...', user: { username: 'bob' } }
]
```

### Nesting

`+` starts from the first table and nests each related table under the row it belongs to, following the foreign keys in your database:

- A table your rows point to is nested as an object, named after the foreign key: `posts.user_id` nests as `user:`.
- A table pointing to your rows is nested as an array, named after the table: `Users[:username] + Posts[:title]` nests each user's posts as `posts: [...]`.

```ruby
Users[:username] + Posts[:title] + Comments[:body]
# => [
#   { username: 'alice', posts: [{ title: 'Hello', comments: [{ body: 'Nice' }] }] },
#   { username: 'carol', posts: [] }
# ]
```

Every row of the first table appears exactly once, so rows never repeat or drop out, and sibling tables such as `Posts + Comments + Likes` nest side by side. The tables after the first can be written in any order. `+` runs one query per table, so call `to_a` rather than `sql`. It raises when foreign keys link the tables by more than one path, or when more than one foreign key links two tables.

#### Brackets

Tables can also nest inside another table's brackets, which nests them directly under that table. The code then has the shape of the output:

```ruby
Users[:username, Posts[:title, Likes[]]]
# => [{ username: 'alice', posts: [{ title: 'Hello', likes: [{ id: 1, ... }] }] }]
```

`+` is shorthand for this where LowData can work out the structure from foreign keys: `Posts[:title] + Users[:username]` returns the same data as `Posts[:title, Users[:username]]`. Parentheses group a `+` chain, so `Users + (Posts + Likes)` nests likes under posts.

A keyword names a nested table. On the "one" side the name also picks the foreign key, so the same table can nest twice:

```ruby
Reviews[:rating, author: Users[:username], editor: Users[:username]]
# => [{ rating: 5, author: { username: 'alice' }, editor: { username: 'bob' } }]
```

#### Filters

Round brackets `()` after a table name to filter its rows, and square brackets then choose what to return. Inside a repository's methods, keywords filter by Ruby values:

```ruby
Posts(published: true)[:title]          # WHERE published = TRUE
Posts(views: 100..)[:title]             # WHERE views >= 100
Posts(status: %w[draft live])[:title]   # WHERE status IN ('draft', 'live')
Posts(deleted_at: nil)[:title]          # WHERE deleted_at IS NULL
```

A block holds conditions that need more than a value. It's a [Sequel virtual row](https://sequel.jeremyevans.net/rdoc/files/doc/virtual_rows_rdoc.html), so a bare name is a column:

```ruby
Posts { (views > 100) | featured }[:title]   # WHERE views > 100 OR featured
Posts(published: true) { views > minimum }[:title]
```

Combine conditions with `&` and `|`, not `&&` and `||`: Ruby can't overload `&&` and `||`, so `views > 100 && featured` silently becomes `featured`. The block can read local variables, but not the repository's methods or instance variables unless it takes an argument: `Posts { |post| post.views > minimum_views }`.

A table in round brackets keeps the rows that have related rows in it:

```ruby
Users(Posts(published: true))[:username]    # users with a published post
Users(~Posts)[:username]                    # users with no posts
Users(Posts => 3..)[:username]              # users with 3 or more posts
Reviews(author: Users(username: 'alice'))[:rating]   # a name picks the foreign key to follow
```

On a nested table a filter only filters the nested rows: `Users[:username, Posts(published: true)[:title]]` returns every user, each with their published posts. To filter both, reuse the filtered table:

```ruby
published = Posts(published: true)
Users(published)[:username, published[:title]]   # only users with published posts, and only those posts
```

In the SQL joins below, filters go in the `WHERE` clause. To split a long expression over several lines, break inside the brackets and keep `) {` and `}[` together. A `[` at the start of a line starts a new array, silently dropping the columns.

#### Sorting and limits

`^` sorts by the columns in `Col[]`, ascending like an arrow going up, and `-` reverses them. Arithmetic limits the rows:

```ruby
Posts[:title] ^ Col[:views]                    # ORDER BY views
Posts[:title] ^ Col[:views, :title]            # ORDER BY views, title
Posts[:title] ^ -Col[:views]                   # ORDER BY views DESC
Posts[:title] ^ -Col[:views] + Col[:title]     # ORDER BY views DESC, title
Posts[:title] ^ -Col[:views] * 10              # ... LIMIT 10
Posts[:title] ^ -Col[:views][20...40]          # ... LIMIT 20 OFFSET 20
(Posts[:title] ^ -Col[:views] / 20)[2]         # ... LIMIT 20 OFFSET 40, the third page of 20
Posts[:title] * 5                              # LIMIT 5
```

Rows and pages count from 0, as in Ruby. Ruby binds `-`, `+`, `*`, `/` and `[]` tighter than `^`, so a limit travels with its sort and needs no parentheses, except around pages before `[page]`.

Inside brackets, a sort or limit applies to each parent's nested rows:

```ruby
Users[:username, Posts[:title] ^ -Col[:views] * 3] ^ Col[:username]
# => Users alphabetically, each with their 3 most viewed posts
```

After `&`, a sort applies to the joined rows, using whichever table has the column. `<`, `>` and `<=>` bind looser than `^`, so put the join in parentheses: `(Users[] < Posts[]) ^ Col[:username]`. After a `+` chain, a sort applies to the first table.

### Join Operators

The other operators are SQL joins that return flat rows, and the `ON` clause comes from the foreign keys in your database:

| Expression                           | Join            |
|--------------------------------------|-----------------|
| `Users[:username] & Posts[:title]`   | Inner join      |
| `Users[:username] < Posts[:title]`   | Left join       |
| `Users[:username] > Posts[:title]`   | Right join      |
| `Users[:username] <=> Posts[:title]` | Full outer join |

Ruby evaluates `&` before `<` and `>`, so add parentheses when mixing operators: `(Users[] < Posts[]) & Comments[]`. `+` can't be combined with these operators, because it returns nested data rather than rows.

### Data Inversion

Data Expressions can invert the usual database query logic; instead of building a query of what we want from the database, we build the table we want and let the expression build the query.

```ruby
class PostsData < LowData
  def all
    Table[:username, :title, :body]
  end
end
```

This expression returns the same data as the `Posts + Users` example above, flattened into one row per post. It's smart enough to know that we're in a `Posts` repository, and that our `Posts` table has a foreign key of `user_id` to the `Users` table. LowData then connects `:username` to this table automatically.
