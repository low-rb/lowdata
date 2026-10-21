<a href="https://rubygems.org/gems/lowdata" title="Install gem"><img src="https://badge.fury.io/rb/lowdata.svg" alt="Gem version" height="18"></a>

LowData follows the repository pattern with a twist; Data Expressions. Use simple arithmetic to connect tables:

```ruby
class PostsData < LowData
  def all
    Posts[:title, :body] + Users[:username]

    # SELECT title, body, user_id FROM posts
    # SELECT username, id FROM users WHERE (id IN (...))
    # => [
    #   { title: 'Hello', body: '...', user: { username: 'alice' } },
    #   { title: 'World', body: '...', user: { username: 'bob' } }
    # ]
  end
end
```

The above expression returns a list of posts with each post's user nested inside it.

⭐ **Syntax overview:**
```ruby
Posts(published: true)[:title, User[:username]] ^ Col[created_at:] * 10

└─┬─┘└───────┬───────┘ └─┬──┘  └──────┬──────┘  └───────┬────────┘ └┬─┘
Table     Filter       Column       Nesting            Sort        Limit
```

✨ **Special characters:**
- `()` - Filtering
- `[]` - Structure
- `^` - Sorting
- `*` - Limit
- `[1..10]` - Range

## Joins

### Inner join

```ruby
Users[:username] & Posts[:title]
# SELECT users.username, posts.title FROM users INNER JOIN posts ON (posts.user_id = users.id)
```

### Left join

```ruby
Users[:username] < Posts[:title]
# SELECT users.username, posts.title FROM users LEFT JOIN posts ON (posts.user_id = users.id)
```

### Right join

```ruby
Users[:username] > Posts[:title]
# SELECT users.username, posts.title FROM users RIGHT JOIN posts ON (posts.user_id = users.id)
```

### Full outer join

```ruby
Users[:username] <=> Posts[:title]
# SELECT users.username, posts.title FROM users FULL JOIN posts ON (posts.user_id = users.id)
```

The `ON` clause comes from the foreign keys in your database.

Ruby evaluates `&` before `<` and `>`, so add parentheses when mixing operators: `(Users[] < Posts[]) & Comments[]`. `+` returns nested data rather than rows, so its result can't be joined, but a join can be [nested with `+`](#nesting-joins).

## Data Inversion

Data Expressions can invert the usual database query logic; instead of building a query of what we want from the database, we build the table we want and let the expression build the query.

```ruby
class PostsData < LowData
  def all
    Table[:username, :title, :body]

    # SELECT users.username, posts.title, posts.body FROM posts LEFT JOIN users ON (posts.user_id = users.id)
  end
end
```

This expression returns the same data as the `Posts + Users` example above, flattened into one row per post. It's smart enough to know that we're in a `Posts` repository, and that our `Posts` table has a foreign key of `user_id` to the `Users` table. LowData then connects `:username` to this table automatically.

## Nesting

### Flat nesting

`+` starts from the first table and nests each related table under the row it belongs to, following the foreign keys in your database:

- A table your rows point to is nested as an object, named after the foreign key: `posts.user_id` nests as `user:`.
- A table pointing to your rows is nested as an array, named after the table: `Users[:username] + Posts[:title]` nests each user's posts as `posts: [...]`.

```ruby
Users[:username] + Posts[:title] + Comments[:body]

# SELECT username, id FROM users
# SELECT title, user_id, id FROM posts WHERE (user_id IN (...))
# SELECT body, post_id FROM comments WHERE (post_id IN (...))
# => [
#   { username: 'alice', posts: [{ title: 'Hello', comments: [{ body: 'Nice' }] }] },
#   { username: 'carol', posts: [] }
# ]
```

Every row of the first table appears exactly once, so rows never repeat or drop out, and sibling tables such as `Posts + Comments + Likes` nest side by side. The tables after the first can be written in any order. `+` runs one query per table, so call `to_a` rather than `sql`. It raises when foreign keys link the tables by more than one path, or when more than one foreign key links two tables.

### Inline nesting

Tables can also nest inside another table so that the input has the shape of the output:

```ruby
Users[:username, Posts[:title, Likes[]]]

# SELECT username, id FROM users
# SELECT title, user_id, id FROM posts WHERE (user_id IN (...))
# SELECT likes.* FROM likes WHERE (post_id IN (...))
# => [{ username: 'alice', posts: [{ title: 'Hello', likes: [{ id: 1, ... }] }] }]
```

`+` is shorthand for this where LowData can work out the structure from foreign keys: `Posts[:title] + Users[:username]` returns the same data as `Posts[:title, Users[:username]]`. Parentheses group a `+` chain, so `Users + (Posts + Likes)` nests likes under posts.

A keyword names a nested table. On the "one" side the name also picks the foreign key, so the same table can nest twice:

```ruby
Reviews[:rating, author: Users[:username], editor: Users[:username]]

# SELECT rating, author_id, editor_id FROM reviews
# SELECT username, id FROM users WHERE (id IN (...))
# SELECT username, id FROM users WHERE (id IN (...))
# => [{ rating: 5, author: { username: 'alice' }, editor: { username: 'bob' } }]
```

### Nesting joins

A join nests as flat rows, under the one table in it that links to the parent:

```ruby
Users[:username] + (Posts[:title] & Comments[:body])

# SELECT username, id FROM users
# SELECT posts.title, comments.body, posts.user_id AS lowdata_link FROM posts INNER JOIN comments ON (comments.post_id = posts.id) WHERE (posts.user_id IN (...))
# => [{ username: 'alice', posts: [{ title: 'Hello', body: 'Nice' }] }, { username: 'bob', posts: [] }]
```

The join keeps the rows its operator keeps, so `<` would also keep posts without comments. A join can also nest in brackets, and filters apply to the joined rows.

A sort or limit inside the parentheses applies to each parent's joined rows, by a column from any table in the join:

```ruby
Users[:username] + (Posts[:title] & Comments[:body] ^ Col[:body] * 2)

# SELECT username, id FROM users
# SELECT * FROM (
#   SELECT posts.title, comments.body, posts.user_id AS lowdata_link,
#     row_number() OVER (PARTITION BY posts.user_id ORDER BY comments.body) AS lowdata_row_number
#   FROM posts INNER JOIN comments ON (comments.post_id = posts.id) WHERE (posts.user_id IN (...))
# ) AS t1 WHERE ((lowdata_row_number >= 1) AND (lowdata_row_number <= 2)) ORDER BY lowdata_row_number
# => Users, each with their first 2 post and comment rows by comment body
```

- Ruby runs `*`, then `&`, then `^`, so the example above is `(Posts[:title] & Comments[:body]) ^ (Col[:body] * 2)`.
- `<`, `>` and `<=>` run after `^`, so those joins need parentheses of their own: `(Posts[] < Comments[]) ^ Col[:body]`.
- A sort after the closing parenthesis sorts the parents instead.

Only the "many" side can nest a join, because joined rows can repeat the row they link to. Tables can't nest under a join, because it returns flat rows.

```ruby
(Users[:username] & Posts[:title]) + Comments[:body]
# => LowData::JoinError: A join returns flat rows, so tables can't nest under it
```

## Filters

Use round brackets `()` after a table name to filter its rows (square brackets are the structure; columns, tables).

```ruby
Posts(published: true)[:title]
# SELECT posts.title FROM posts WHERE (posts.published = TRUE)

Posts(views: 100..)[:title]
# SELECT posts.title FROM posts WHERE (posts.views >= 100)

Posts(status: %w[draft live])[:title]
# SELECT posts.title FROM posts WHERE (posts.status IN ('draft', 'live'))

Posts(deleted_at: nil)[:title]
# SELECT posts.title FROM posts WHERE (posts.deleted_at IS NULL)
```

A block holds conditions that need more than a value. It's a [Sequel virtual row](https://sequel.jeremyevans.net/rdoc/files/doc/virtual_rows_rdoc.html) and a variable references a column:

```ruby
Posts { (views > 100) | featured }[:title]
# SELECT posts.title FROM posts WHERE ((posts.views > 100) OR posts.featured)

Posts(published: true) { views > minimum }[:title]
# SELECT posts.title FROM posts WHERE ((posts.published = TRUE) AND (posts.views > 50)), when minimum is 50
```

Combine conditions with `&` and `|`, not `&&` and `||`: Ruby can't overload `&&` and `||`, so `views > 100 && featured` silently becomes `featured`. The block can read local variables, but not the repository's methods or instance variables unless it takes an argument: `Posts { |post| post.views > minimum_views }`.

A table in round brackets keeps the rows that have related rows in it:

```ruby
Users(Posts(published: true))[:username] # Users with a published post.
# SELECT users.username FROM users WHERE (EXISTS (SELECT 1 FROM posts WHERE ((posts.user_id = users.id) AND (posts.published = TRUE))))

Users(~Posts)[:username] # Users with no posts.
# SELECT users.username FROM users WHERE NOT (EXISTS (SELECT 1 FROM posts WHERE (posts.user_id = users.id)))

Users(Posts => 3..)[:username] # Users with 3 or more posts.
# SELECT users.username FROM users WHERE ((SELECT count(*) FROM posts WHERE (posts.user_id = users.id)) >= 3)

Reviews(author: Users(username: 'alice'))[:rating] # A name picks the foreign key to follow.
# SELECT reviews.rating FROM reviews WHERE (EXISTS (SELECT 1 FROM users WHERE ((users.id = reviews.author_id) AND (users.username = 'alice'))))
```

On a nested table a filter only filters the nested rows: `Users[:username, Posts(published: true)[:title]]` returns every user, each with their published posts. To filter both, reuse the filtered table:

```ruby
published = Posts(published: true)
Users(published)[:username, published[:title]] # only users with published posts, and only those posts

# SELECT username, id FROM users WHERE (EXISTS (SELECT 1 FROM posts WHERE ((posts.user_id = users.id) AND (posts.published = TRUE))))
# SELECT title, user_id FROM posts WHERE ((posts.published = TRUE) AND (user_id IN (...)))
```

In the SQL joins below, filters go in the `WHERE` clause. To split a long expression over several lines, break inside the brackets and keep `) {` and `}[` together. A `[` at the start of a line starts a new array, silently dropping the columns.

## Sorting

`^` sorts by the columns in `Col[]`, ascending like an arrow going up, and `-` reverses them. Arithmetic limits the rows:

```ruby
Posts[:title] ^ Col[:views]
# SELECT posts.title FROM posts ORDER BY posts.views

Posts[:title] ^ Col[:views, :title]
# SELECT posts.title FROM posts ORDER BY posts.views, posts.title

Posts[:title] ^ -Col[:views]
# SELECT posts.title FROM posts ORDER BY posts.views DESC

Posts[:title] ^ -Col[:views] + Col[:title]
# SELECT posts.title FROM posts ORDER BY posts.views DESC, posts.title
```

## Limits

```ruby
Posts[:title] * 10
# SELECT posts.title FROM posts LIMIT 10

Posts[:title][20...40]
# SELECT posts.title FROM posts ORDER BY posts.views DESC LIMIT 20 OFFSET 20

(Posts[:title] / 20)[2] # the third page of 20
# SELECT posts.title FROM posts LIMIT 20 OFFSET 40

Posts[:title] * 5
# SELECT posts.title FROM posts LIMIT 5
```

Rows and pages count from 0, as in Ruby. Ruby binds `-`, `+`, `*`, `/` and `[]` tighter than `^`, so a limit travels with its sort and needs no parentheses, except around pages before `[page]`.

Inside brackets, a sort or limit applies to each parent's nested rows:

```ruby
Users[:username, Posts[:title] ^ -Col[:views] * 3] ^ Col[:username]

# SELECT username, id FROM users ORDER BY users.username
# SELECT * FROM (
#   SELECT title, user_id, row_number() OVER (PARTITION BY posts.user_id ORDER BY posts.views DESC) AS lowdata_row_number
#   FROM posts WHERE (user_id IN (...))
# ) AS t1 WHERE ((lowdata_row_number >= 1) AND (lowdata_row_number <= 3)) ORDER BY lowdata_row_number
# => Users alphabetically, each with their 3 most viewed posts
```

After `&`, a sort applies to the joined rows, using whichever table has the column. `<`, `>` and `<=>` bind looser than `^`, so put the join in parentheses: `(Users[] < Posts[]) ^ Col[:username]`. After a `+` chain, a sort applies to the first table.
