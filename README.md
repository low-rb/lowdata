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

| Expression                           | Join                                                       |
|--------------------------------------|------------------------------------------------------------|
| `Users[:username] + Posts[:title]`   | Many-to-one join; every post once, with its user's columns |
| `Users[:username] & Posts[:title]`   | Inner join                                                 |
| `Users[:username] < Posts[:title]`   | Left join                                                  |
| `Users[:username] > Posts[:title]`   | Right join                                                 |
| `Users[:username] <=> Posts[:title]` | Full outer join                                            |

`+` is a many-to-one join: it keeps every row of the subject exactly once, as a left join, and adds columns from the tables those rows point to. The subject is the one table nothing else in the expression points to (the "many" side, such as posts to their one user), so `+` never repeats or drops rows and the order you write tables in doesn't matter: `Users + Posts + Comments` and `Comments + Posts + Users` both return every comment with its post's title and its user's username.

When two tables point to the same table, such as `Posts + Comments + Likes`, there's no single table to keep and `+` raises. Use [Data Inversion](#data-inversion) or explicit joins instead: `(Users[] > Posts[]) < Comments[]` returns every post with its comments.

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
