<a href="https://rubygems.org/gems/lowdata" title="Install gem"><img src="https://badge.fury.io/rb/lowdata.svg" alt="Gem version" height="18"></a>

LowData follows the repository pattern with a twist; *Data Expressions*. Data Expressions are just that, they are values, that represent a table and its columns (`TableName[:column]`). LowData then uses simple arithmetic to connect these tables together:
- `+` combines tables (usually [nesting](#nesting) data into the parent)
- `*` describes how many results you want
- `&`, `<`,`>` [joins](#joins) tables together

**For example this expression:**
```ruby
class PostsData < LowData
  def all
    Posts[:title, :body] + Users[:username]
  end
end
```

...generates this SQL query:
```sql
SELECT title, body, user_id FROM posts
SELECT username, id FROM users WHERE (id IN (...))
```

...which results in a list of posts with each post's user nested inside it:
```ruby
[
  { title: 'Hello', body: '...', user: { username: 'alice' } },
  { title: 'World', body: '...', user: { username: 'bob' } }
]
```

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

Every row of the first table appears exactly once, so rows never repeat or drop out. Each table nests in the table written before it, so the expression has the shape of the result. Tables nested side by side go in an array:

```ruby
Posts[:title] + [Comments[:body], Likes[]]

# SELECT title, id FROM posts
# SELECT body, post_id FROM comments WHERE (post_id IN (...))
# SELECT likes.* FROM likes WHERE (post_id IN (...))
# => [{ title: 'Hello', comments: [{ body: 'Nice' }], likes: [{ id: 1, ... }, { id: 2, ... }] }]
```

An array's elements can be chains, and an array ends a chain: `Users + [Posts + Comments, Orders]` nests posts with their comments, and orders, in each user. A table can also reach back to an earlier table by naming its foreign key in round brackets: `Users + Posts + Orders(:user_id)` nests orders in users, beside posts.

> [!NOTE]
> **`+` follows position. Foreign keys only decide how each table links to the one before it.**
>
> In `Users + Posts + Comments`, comments link to posts by `comments.post_id`. If comments also have a `user_id`, it's ignored, because comments are written next to posts, not users. So a foreign key added between other tables can't change or break the expression.

### Inline nesting

Tables can also nest inside another table so that the input has the shape of the output:

```ruby
Users[:username, Posts[:title, Likes[]]]

# SELECT username, id FROM users
# SELECT title, user_id, id FROM posts WHERE (user_id IN (...))
# SELECT likes.* FROM likes WHERE (post_id IN (...))
# => [{ username: 'alice', posts: [{ title: 'Hello', likes: [{ id: 1, ... }] }] }]
```

`+` is another way to write this: `Users[:username] + Posts[:title] + Likes[]` returns the same data as the example above, and `Posts[:title] + Users[:username]` the same as `Posts[:title, Users[:username]]`.

A keyword names a nested table. On the "one" side the name also picks the foreign key, so the same table can nest twice:

```ruby
Reviews[:rating, author: Users[:username], editor: Users[:username]]

# SELECT rating, author_id, editor_id FROM reviews
# SELECT username, id FROM users WHERE (id IN (...))
# SELECT username, id FROM users WHERE (id IN (...))
# => [{ rating: 5, author: { username: 'alice' }, editor: { username: 'bob' } }]
```

### Nesting joins

A [join](#joins) nests as flat rows, linked through its first table, the one written next to the `+`:

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

Only the "many" side can nest a join, because joined rows can repeat the row they link to.

Because the join links through the table next to the `+`, `Users[:username] + (Posts[:title] & Likes[:id])` nests through `posts.user_id`, although likes have a `user_id` too. To link through another of its tables, name its foreign key: `Likes(:user_id)`.

**Use case:** a many-to-many relationship through a join table, such as posts with their tags through `post_tags`. Nesting the join gives each post a flat list of tags, where `Posts + PostTags + Tags` would nest each tag inside its `post_tags` row:

```ruby
Posts[:title] + (PostTags[:created_at] & Tags[:name])

# SELECT title, id FROM posts
# SELECT post_tags.created_at, tags.name, post_tags.post_id AS lowdata_link FROM post_tags INNER JOIN tags ON (post_tags.tag_id = tags.id) WHERE (post_tags.post_id IN (...))
# => [
#   { title: 'Hello', post_tags: [{ created_at: 2026-10-01, name: 'ruby' }, { created_at: 2026-10-02, name: 'sql' }] },
#   { title: 'World', post_tags: [] }
# ]
```

The tags nest under `post_tags`, the table that links them to posts. To name them `tags`, nest the join [in square brackets](#inline-nesting) instead: `Posts[:title, tags: PostTags[:created_at] & Tags[:name]]`.

### Nesting under joins

Tables can also nest under a join. Each joined row gets its own nested rows, through the join's last table, the one written next to the `+`:

```ruby
(Users[:username] & Posts[:title]) + Comments[:body]

# SELECT users.username, posts.title, posts.id AS lowdata_posts_id FROM users INNER JOIN posts ON (posts.user_id = users.id)
# SELECT body, post_id FROM comments WHERE (post_id IN (...))
# => [
#   { username: 'alice', title: 'Hello', comments: [{ body: 'Nice' }] },
#   { username: 'bob', title: 'World', comments: [] }
# ]
```

As with tables, a table the joined rows point to nests as an object: `(Comments[:body] & Posts[:title]) + Users[:username]` nests each row's `user:`.

**Use case:** a report of flat rows, each with its own details, such as orders with their customer's name and their line items, largest first:

```ruby
(Customers[:name] & Orders[:total]) + LineItems[:product, :quantity] ^ -Col[:total]

# SELECT customers.name, orders.total, orders.id AS lowdata_orders_id FROM customers INNER JOIN orders ON (orders.customer_id = customers.id) ORDER BY orders.total DESC
# SELECT product, quantity, order_id FROM line_items WHERE (order_id IN (...))
# => [
#   { name: 'Acme', total: 120, line_items: [{ product: 'Anvil', quantity: 2 }, { product: 'Rope', quantity: 1 }] },
#   { name: 'Globex', total: 80, line_items: [{ product: 'Lamp', quantity: 4 }] }
# ]
```

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

The `ON` clause comes from the foreign keys in your database. Each table joins to the table written before it, using only the foreign keys between the two. To join to an earlier table, name its foreign key: `Posts[:title] & Users[:username] & Orders(:user_id)[:total]` joins orders to users.

Ruby evaluates `&` before `<` and `>`, so add parentheses when mixing operators: `(Users[] < Posts[]) & Comments[]`. `+` returns nested data rather than rows, so its result can't be joined, but a join can be [nested with `+`](#nesting-joins).

## Renaming

Rows are hashes, so when joined tables share a column name, only one value can be returned. A keyword with a symbol returns a column under a new name:

```ruby
Users[:username, user_id: :id] & Posts[:title, post_id: :id]
# SELECT users.username, users.id AS user_id, posts.title, posts.id AS post_id FROM users INNER JOIN posts ON (posts.user_id = users.id)
# => [{ username: 'alice', user_id: 1, title: 'Hello', post_id: 1 }]

Posts[:id, headline: :title]
# SELECT posts.id, posts.title AS headline FROM posts
# => [{ id: 1, headline: 'Hello' }]
```

As with [named nested tables](#inline-nesting), the key is what you get back and the value is where it comes from. Renames work in nested tables, joins and `Table[]`, and they go last in the brackets, because Ruby puts keywords after other arguments: `Users[Posts[:title], handle: :username]`, or with `+`, `Users[handle: :username] + Posts[:title]`.

A rename written backwards raises with the fix: `Posts[title: :headline]` raises "posts has no headline column. To rename title, write headline: :title". Sort by the column, not the new name: `Posts[headline: :title] ^ Col[:title]`.

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
# Users with a published post.
Users(Posts(published: true))[:username]
# SELECT users.username FROM users WHERE (EXISTS (SELECT 1 FROM posts WHERE ((posts.user_id = users.id) AND (posts.published = TRUE))))

# Users with no posts.
Users(~Posts)[:username]
# SELECT users.username FROM users WHERE NOT (EXISTS (SELECT 1 FROM posts WHERE (posts.user_id = users.id)))

# Users with 3 or more posts.
Users(Posts => 3..)[:username]
# SELECT users.username FROM users WHERE ((SELECT count(*) FROM posts WHERE (posts.user_id = users.id)) >= 3)

# A name picks the foreign key to follow.
Reviews(author: Users(username: 'alice'))[:rating]
# SELECT reviews.rating FROM reviews WHERE (EXISTS (SELECT 1 FROM users WHERE ((users.id = reviews.author_id) AND (users.username = 'alice'))))
```

On a nested table a filter only filters the nested rows: `Users[:username] + Posts(published: true)[:title]` returns every user, each with their published posts. To filter both, reuse the filtered table:

```ruby
# Only users with published posts, and only those posts.
published = Posts(published: true)
Users(published)[:username] + published[:title]

# SELECT username, id FROM users WHERE (EXISTS (SELECT 1 FROM posts WHERE ((posts.user_id = users.id) AND (posts.published = TRUE))))
# SELECT title, user_id FROM posts WHERE ((posts.published = TRUE) AND (user_id IN (...)))
```

In [SQL joins](#joins), filters go in the `WHERE` clause. To split a long expression over several lines, see [Multi-line expressions](#multi-line-expressions).

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

On a nested table, a sort or limit applies to each parent's nested rows:

```ruby
Users[:username] + (Posts[:title] ^ -Col[:views] * 3) ^ Col[:username]

# SELECT username, id FROM users ORDER BY users.username
# SELECT * FROM (
#   SELECT title, user_id, row_number() OVER (PARTITION BY posts.user_id ORDER BY posts.views DESC) AS lowdata_row_number
#   FROM posts WHERE (user_id IN (...))
# ) AS t1 WHERE ((lowdata_row_number >= 1) AND (lowdata_row_number <= 3)) ORDER BY lowdata_row_number
# => Users alphabetically, each with their 3 most viewed posts
```

After `&`, a sort applies to the joined rows, using whichever table has the column. `<`, `>` and `<=>` bind looser than `^`, so put the join in parentheses: `(Users[] < Posts[]) ^ Col[:username]`. After a `+` chain, a sort applies to the first table.

## Syntax

⭐ **Overview:**
```ruby
Posts(published: true)[:title] + Users[:username] ^ Col[:created_at] * 10

└─┬─┘└───────┬───────┘└──┬───┘ └───────┬────────┘ └───────┬────────┘ └┬─┘
Table     Filters     Columns       Nesting            Sorting       Limit
```

✨ **Symbols:**
- `()` - Filtering
- `[]` - Structure
- `^` - Sorting
- `*` - Limit
- `/ 2` - Pagination
- `[1..10]` - Range

## Multi-line expressions

Expressions are plain Ruby values that don't run until they're used, so they can be split over lines, named and built from other methods.

**One table per line.** End each line with its operator:

```ruby
Users[:username] +
  Posts(published: true)[:title] +
  Comments[:body]
```

Ruby ends a statement at a line break when the line is complete, even inside parentheses, so an operator at the start of the next line begins a new statement. A leading `+` raises `undefined method '+@'`, and a leading `&`, `<`, `^` or `*` is a syntax error.

**Long brackets.** Break inside the brackets, with the columns on one line and each nested table on its own:

```ruby
Reviews[
  :rating, :title,
  author: Users[:username],
  editor: Users[:username]
]
```

With a filter, keep `) {` and `}[` together:

```ruby
Posts(published: true) {
  views > 100
}[
  :title, :views,
  Users[:username]
]
```

Split anywhere else and Ruby reads the next line as a new statement. A `{` at the start of a line is a hash, which is a syntax error. A `[` at the start of a line is a new array, which fails silently:

```ruby
Posts(published: true) { views > 100 }
[:title, :views] # A new array, so the method returns [:title, :views] instead of posts
```

**Name the parts.** A local variable gives a dense part, such as a per-parent sort and limit, a name:

```ruby
top_posts = Posts[:title] ^ -Col[:views] * 3
Users[:username] + top_posts ^ Col[:username]
```

**Build from methods.** Repository methods return expressions, so they combine like any other:

```ruby
class UsersData < LowData
  def published_posts = Posts(published: true)[:title]
  def authors = Users[:username] + published_posts
end
```

Each method is short, named and can be tested on its own, and `authors` reads like a sentence.
