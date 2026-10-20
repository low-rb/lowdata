<a href="https://rubygems.org/gems/lowdata" title="Install gem"><img src="https://badge.fury.io/rb/lowdata.svg" alt="Gem version" height="18"></a>

## LowData [UNRELEASED]

Instead of the model defining relationships and associated queries to the database, LowData follows the repository pattern with a twist; Data Expressions.

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

A keyword with any other value filters that table's rows, using Ruby values:

```ruby
Posts[:title, published: true]          # WHERE published = TRUE
Posts[:title, views: 100..]             # WHERE views >= 100
Posts[:title, status: %w[draft live]]   # WHERE status IN ('draft', 'live')
Posts[:title, deleted_at: nil]          # WHERE deleted_at IS NULL
```

On a nested table a filter only filters the nested rows: `Users[:username, Posts[:title, published: true]]` returns every user, each with their published posts. In the SQL joins below, filters go in the `WHERE` clause.

Ruby needs positional arguments before keyword arguments, so write columns and unnamed tables first: `Posts[:title, Likes[], published: true]`.

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
