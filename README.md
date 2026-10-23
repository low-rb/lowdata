<a href="https://rubygems.org/gems/lowdata" title="Install gem"><img src="https://badge.fury.io/rb/lowdata.svg" alt="Gem version" height="18"></a>

LowData is the repository pattern with a twist: *Data Expressions*. An expression represents a table and its columns; `TableName[:column]`, and operators combine them:
- `+` combines tables (usually [nesting](#nesting) data into the parent)
- `^` [sorts](#sorting) and `*` describes how many results you want
- `&`, `<`, `>`, `<=>` [joins](#joins) tables together
- `<<`, `<=`, `[]=` [write](#writes) rows

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

### Chained nesting

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

Each row of the first table appears once, and each table nests in the one before it, so the expression has the shape of the result. Put tables side by side in an array:

```ruby
Posts[:title] + [Comments[:body], Likes]

# SELECT title, id FROM posts
# SELECT body, post_id FROM comments WHERE (post_id IN (...))
# SELECT likes.* FROM likes WHERE (post_id IN (...))
# => [{ title: 'Hello', comments: [{ body: 'Nice' }], likes: [{ id: 1, ... }, { id: 2, ... }] }]
```

Array items can be chains: `Users + [Posts + Comments, Orders]`. To nest in an earlier table, name its foreign key: `Users + Posts + Orders(:user_id)` nests orders in users.

> [!NOTE]
> **`+` follows position. Foreign keys only link each table to the one before it.**
>
> In `Users + Posts + Comments`, comments link to posts by `comments.post_id`, even if they also have a `user_id`. So adding a foreign key elsewhere can't change the result.

### Inline nesting

Tables can also nest inside another table so that the input has the shape of the output:

```ruby
Users[:username, Posts[:title, Likes]]

# SELECT username, id FROM users
# SELECT title, user_id, id FROM posts WHERE (user_id IN (...))
# SELECT likes.* FROM likes WHERE (post_id IN (...))
# => [{ username: 'alice', posts: [{ title: 'Hello', likes: [{ id: 1, ... }] }] }]
```

`+` is another way to write this: `Users[:username] + Posts[:title] + Likes` returns the same data as the example above, and `Posts[:title] + Users[:username]` the same as `Posts[:title, Users[:username]]`.

A keyword names a nested table, and `author:` follows `author_id`, so the same table can nest twice:

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

The operator decides which rows the join keeps: `<` also keeps posts without comments. Joins can nest in brackets too, and filters apply to the joined rows.

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
- `<`, `>` and `<=>` run after `^`, so those joins need parentheses of their own: `(Posts < Comments) ^ Col[:body]`.
- A sort after the closing parenthesis sorts the parents instead.

Only the "many" side can nest a join, because joined rows can repeat the row they link to.

`Users[:username] + (Posts[:title] & Likes[:id])` links through `posts.user_id`, the table next to the `+`, even though likes have a `user_id` too. To link through likes instead, write `Likes(:user_id)`.

**Use case:** many-to-many, such as posts and tags through `post_tags`. Nesting the join gives each post a flat list of tags, rather than tags inside `post_tags` rows:

```ruby
Posts[:title] + (PostTags[:created_at] & Tags[:name])

# SELECT title, id FROM posts
# SELECT post_tags.created_at, tags.name, post_tags.post_id AS lowdata_link FROM post_tags INNER JOIN tags ON (post_tags.tag_id = tags.id) WHERE (post_tags.post_id IN (...))
# => [
#   { title: 'Hello', post_tags: [{ created_at: 2026-10-01, name: 'ruby' }, { created_at: 2026-10-02, name: 'sql' }] },
#   { title: 'World', post_tags: [] }
# ]
```

The tags nest under `post_tags`. To call them `tags`, nest the join [in square brackets](#inline-nesting): `Posts[:title, tags: PostTags[:created_at] & Tags[:name]]`. Use `PostTags[]` to leave out its columns, returning `tags: [{ name: 'ruby' }, { name: 'sql' }]`.

### Nesting under joins

Tables can nest under a join too. Each joined row gets its own nested rows, linked through the join's last table:

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

MySQL has no `FULL JOIN`, so `<=>` raises there; use `<` or `>` instead.

The `ON` clause comes from your foreign keys, and each table joins to the one before it. To join to an earlier table, name its foreign key: `Posts[:title] & Users[:username] & Orders(:user_id)[:total]` joins orders to users.

Ruby runs `&` before `<` and `>`, so mix them with parentheses: `(Users < Posts) & Comments`. `+` returns nested data, so it can't be joined, but a join can be [nested](#nesting-joins).

## Columns

Square brackets choose columns. No brackets means every column, and empty brackets mean none:

| Expression | Columns | SQL |
|---|---|---|
| `Posts` | every column | `SELECT posts.* FROM posts` |
| `Posts[:title]` | the ones listed | `SELECT posts.title FROM posts` |
| `Posts[]` | none | – |

A table without brackets works anywhere: `Users[:username] + Posts`, `Users[:username, Posts]` or `Posts ^ Col[:views]`. Empty brackets keep a table out of the result while it still links and filters rows: `Users[] & Posts[:title]` returns only titles. A query with no columns at all, such as `Posts[]` alone, raises.

## Renaming

Rows are hashes, so joined tables can't both return an `id`. Rename a column with a keyword:

```ruby
Users[:username, user_id: :id] & Posts[:title, post_id: :id]
# SELECT users.username, users.id AS user_id, posts.title, posts.id AS post_id FROM users INNER JOIN posts ON (posts.user_id = users.id)
# => [{ username: 'alice', user_id: 1, title: 'Hello', post_id: 1 }]

Posts[:id, headline: :title]
# SELECT posts.id, posts.title AS headline FROM posts
# => [{ id: 1, headline: 'Hello' }]
```

The key is the new name and the value is the column. Renames work in nested tables, joins and `Table[]`, and go last in the brackets: `Users[Posts[:title], handle: :username]`.

A backwards rename, `Posts[title: :headline]`, raises with the fix. Sort by the column, not the new name: `Posts[headline: :title] ^ Col[:title]`.

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

This returns the `Posts + Users` example above, flattened to one row per post. In `PostsData`, `Table` is posts, and LowData finds `:username` in users through `posts.user_id`.

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

A block holds more complex conditions, where a name is a column ([Sequel virtual rows](https://sequel.jeremyevans.net/rdoc/files/doc/virtual_rows_rdoc.html)):

```ruby
Posts { (views > 100) | featured }[:title]
# SELECT posts.title FROM posts WHERE ((posts.views > 100) OR posts.featured)

Posts(published: true) { views > minimum }[:title]
# SELECT posts.title FROM posts WHERE ((posts.published = TRUE) AND (posts.views > 50)), when minimum is 50
```

Use `&` and `|`, not `&&` and `||`, which Ruby can't overload: `views > 100 && featured` silently becomes `featured`. To use the repository's methods or instance variables, take an argument: `Posts { |post| post.views > minimum_views }`.

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

On a nested table, a filter only filters the nested rows: `Users[:username] + Posts(published: true)[:title]` returns every user. To filter both, reuse the filtered table:

```ruby
# Only users with published posts, and only those posts.
published = Posts(published: true)
Users(published)[:username] + published[:title]

# SELECT username, id FROM users WHERE (EXISTS (SELECT 1 FROM posts WHERE ((posts.user_id = users.id) AND (posts.published = TRUE))))
# SELECT title, user_id FROM posts WHERE ((posts.published = TRUE) AND (user_id IN (...)))
```

In [joins](#joins), filters go in the `WHERE` clause. For long expressions, see [Multi-line expressions](#multi-line-expressions).

## Sorting

`^` sorts ascending by the columns in `Col[]`, like an arrow going up, and `-` reverses them:

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

Rows without a value sort last either way, on every database, so `Posts ^ -Col[:views] * 10` is the 10 most viewed.

## Limits

```ruby
Posts[:title] * 10
# SELECT posts.title FROM posts LIMIT 10

Posts[:title] ^ -Col[:views][20...40]
# SELECT posts.title FROM posts ORDER BY posts.views DESC LIMIT 20 OFFSET 20

(Posts[:title] / 20)[2] # the third page of 20
# SELECT posts.title FROM posts LIMIT 20 OFFSET 40
```

Rows and pages count from 0. A limit binds tighter than `^`, so it needs no parentheses, except around pages before `[page]`.

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

After `&`, a sort uses whichever joined table has the column. Wrap `<`, `>` and `<=>` joins in parentheses first: `(Users < Posts) ^ Col[:username]`. After `+`, a sort applies to the first table.

## Writes

Round brackets choose rows and square brackets choose columns, as in reads, and writes run straight away:

| Write | Syntax | Returns |
|---|---|---|
| Insert | `Posts << { title: 'Hello' }` | the new row |
| Upsert | `Posts(slug: 'hello') <= { title: 'Hello' }` | the row |
| Update | `Posts(id: 1)[:title] = 'New'` | the assigned value |
| Delete | `Posts(id: 1).delete` | the number of rows deleted |

`Table` is the repository's table in writes too, so `def create(post) = Table << post` inserts into `posts` in `PostsData`.

### What goes in and what comes out

Round brackets choose rows, square brackets choose what comes out, and the value on the right goes in. Each row reads left to right:

| Filter | Output | Input |
|---|---|---|
| `Posts(published: true)` | `[:title]` | |
| `Posts(published: true)` | every column | |
| `Posts` | the primary key | `<< { title: 'Hello' }` |
| `Posts` | `[:id, :created_at]` | `<< params.slice(:title, :body)` |
| `Posts` | `[]`, nothing | `<< rows` |
| `Posts(slug: 'hello')` | `[:id]` | `<= { title: 'Hello' }` |
| `Posts(id: 1)` | | `[:title] = 'New'` |
| `Posts(id: 1)` | the number deleted | `.delete` |

Square brackets never filter what goes in, so pick the columns from params yourself, like Rails' `permit`. That way `id` can come out without params setting it. Update is the exception: `Posts(id: 1)[:title] = 'New'` sets the title.

### Insert

`<<` adds rows, as it does to a Ruby array. It returns the new row's primary key, or the columns in square brackets:

```ruby
Posts << { title: 'Hello', user_id: 1 }
# INSERT INTO posts (title, user_id) VALUES ('Hello', 1) RETURNING id
# => { id: 7 }

Posts[:id, :created_at] << { title: 'Hello', user_id: 1 }
# => { id: 7, created_at: 2026-10-22 ... }

Posts << [{ title: 'Hello' }, { title: 'World' }]
# => [{ id: 7 }, { id: 8 }], in one transaction
```

Empty brackets return nothing, which inserts many rows in one statement rather than one by one:

```ruby
Posts[] << [{ title: 'Hello' }, { title: 'World' }]
# INSERT INTO posts (title) VALUES ('Hello'), ('World')
# => [{}, {}]
```

An insert adds new rows, so round brackets raise: `Posts(slug: 'hello') << row` is an upsert.

### Upsert

`<=` adds a row, or updates the matching one. Round brackets name the columns to match, and are written too:

```ruby
Posts(slug: 'hello') <= { title: 'Hello' }
# INSERT INTO posts (slug, title) VALUES ('hello', 'Hello')
#   ON CONFLICT (slug) DO UPDATE SET title = excluded.title RETURNING id
# => { id: 7 }

Posts <= { id: 7, title: 'Hello' } # Without round brackets, the primary key matches.
```

The matched columns need a unique index, and round brackets take plain values only. On MySQL, which matches any unique key, the row mustn't set every column of another unique key.

⚠️ **RuboCop's autocorrect can break an upsert:** `Lint/Void` deletes it and `Style/YodaCondition` reverses it. Turn both off with LowData's config:

```yaml
# .rubocop.yml
inherit_gem:
  lowdata: config/rubocop.yml
```

Under `ruby -w`, an upsert mid-method warns `possibly useless use of <= in void context`. Silence it with the [warning](https://github.com/jeremyevans/ruby-warning) gem: `Warning.ignore(/useless use of <= in void context/)`.

### Update

`[]=` changes the rows chosen by the round brackets, which take any filter:

```ruby
Posts(id: 1)[:title] = 'New'
# UPDATE posts SET title = 'New' WHERE (posts.id = 1)

Posts(id: 1)[:title, :body] = ['New', '...']
Posts(published: false) { created_at < cutoff }[] = { archived: true }
Users(~Posts)[:active] = false
```

Ruby makes an assignment return its right-hand side, so an update returns the assigned value rather than a count.

### Delete

`delete` removes the rows in round brackets and returns how many. It's a word, not an operator, so it's easy to spot:

```ruby
Posts(id: 1).delete
# DELETE FROM posts WHERE (posts.id = 1)
# => 1
```

### Every row

Without round brackets, an update or delete would change every row, so it raises:

```ruby
Posts[:archived] = true # Raises: Choose the posts to update with round brackets, e.g. Posts(id: 1)[:archived] = true
Posts.delete            # Raises: Choose the posts to delete with round brackets, e.g. Posts(id: 1).delete
```

To change every row on purpose, use the dataset: `Posts.dataset.update(archived: true)`.

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

A line starting with an operator is a new statement in Ruby: a leading `+` raises `undefined method '+@'`, and `&`, `<`, `^` or `*` is a syntax error.

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

Split anywhere else and Ruby starts a new statement. A line starting with `{` is a syntax error, and one starting with `[` is a new array, which fails silently:

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
