<a href="https://rubygems.org/gems/lowdata" title="Install gem"><img src="https://badge.fury.io/rb/lowdata.svg" alt="Gem version" height="18"></a>

## LowData [UNRELEASED]

Instead of the model defining relationships and associated queries to the database, LowData follows the repository pattern with a twist; Data Expressions.

This expression joins the `posts` table with the `users` table while representing a join conceptually as simple arithmetic:

```ruby
class PostsData < LowData
  def all
    Users[:username] + Posts[:title, :body]
  end
end
```

The above expression generates SQL to join the user table with the posts table and results in a list of posts with the user's username included in each row.

### Join Operators

Each operator is a type of join, and the `ON` clause comes from the foreign keys in your database:

| Expression                           | Join                                                     |
|--------------------------------------|----------------------------------------------------------|
| `Users[:username] + Posts[:title]`   | Relationship join; every row of the table with the foreign key |
| `Users[:username] & Posts[:title]`   | Inner join                                               |
| `Users[:username] < Posts[:title]`   | Left join                                                |
| `Users[:username] > Posts[:title]`   | Right join                                               |
| `Users[:username] <=> Posts[:title]` | Full outer join                                          |

`+` adds the columns of a related table to the rows of the table holding the foreign key, so `Users + Posts` and `Posts + Users` both return every post.

In a chain, `+` returns the rows of the table furthest down the foreign keys, in any order: `Users + Posts + Comments` and `Comments + Posts + Users` both return every comment. To keep every post instead, use [Data Inversion](#data-inversion) or explicit joins: `(Users[] > Posts[]) < Comments[]`.

Ruby evaluates `+` before `&`, and `&` before `<` and `>`, so add parentheses when mixing operators: `(Users[] < Posts[]) & Comments[]`.

### Data Inversion

Data Expressions can invert the usual database query logic; instead of building a query of what we want from the database, we build the table we want and let the expression build the query.

```ruby
class PostsData < LowData
  def all
    Table[:username, :title, :body]
  end
end
```

This expression generates equivalent SQL to the `Users + Posts` example above. It's smart enough to know that we're in a `Posts` repository, and that our `Posts` table has a foreign key of `user_id` to the `Users` table. LowData then connects `:username` to this table automatically.
