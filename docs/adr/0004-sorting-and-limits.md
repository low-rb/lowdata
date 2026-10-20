# ADR 0004: Sorting with `^ Col[]` and limits with arithmetic

- **Status:** Accepted
- **Date:** 2026-10-21

## Context

[ADR 0003](0003-round-bracket-filters.md) gave filters their own brackets. Data expressions still can't sort or limit their rows, including the rows of nested tables ("each user's 3 most viewed posts").

LowData presents queries as arithmetic: joins are operators, and `+` nests. Sorting and limits should read the same way, without changing Ruby's core classes and without silent failures caused by Ruby's operator precedence.

## Decision

`^` sorts by a `Col`, and `*` and `/` limit and page:

```ruby
Posts(published: true)[:title, :views] ^ -Col[:views] * 10
#     which rows       what to return  sort order    how many
```

### Sorting: `^ Col[...]`

`Col` is a reserved constant, like `Table`. `Col[...]` names the columns to sort by, and `^` sorts the expression by them. `^` looks like an arrow going up, and sorts ascend by default:

| Syntax | SQL |
|---|---|
| `Posts[:title] ^ Col[:views]` | `ORDER BY views` |
| `Posts[:title] ^ Col[:views, :title]` | `ORDER BY views, title` |
| `Posts[:title] ^ -Col[:views]` | `ORDER BY views DESC` |
| `Posts[:title] ^ -Col[:views, :title]` | `ORDER BY views DESC, title DESC` |
| `Posts[:title] ^ -Col[:views] + Col[:title]` | `ORDER BY views DESC, title` |

- **Unary `-` reverses** every column in its `Col`, as `sort_by { -x }` does in Ruby. `+` joins sort keys in the order written.
- **Sorting twice appends:** `Posts[] ^ Col[:views] ^ Col[:title]` is the same as `^ Col[:views] + Col[:title]`.
- **A sort column doesn't have to be selected,** and sorting doesn't select it.

### Limits and pages: arithmetic

| Syntax | Meaning | SQL |
|---|---|---|
| `Posts[:title] * 10` | 10 rows | `LIMIT 10` |
| `(Posts[:title] / 20)[2]` | pages of 20, the third page | `LIMIT 20 OFFSET 40` |
| `Posts[:title] ^ -Col[:views] * 10` | the 10 most viewed | `ORDER BY views DESC LIMIT 10` |
| `Posts[:title] ^ -Col[:views][20...40]` | rows 20 to 39 by views | `ORDER BY views DESC LIMIT 20 OFFSET 20` |
| `Posts[:title] ^ -Col[:views][20..]` | every row from row 20 | `ORDER BY views DESC OFFSET 20` |

- **`*` limits, and `/` splits into pages,** with `[page]` picking one. A range on a `Col` picks rows directly.
- **Rows and pages count from 0, as in Ruby,** so a URL's `?page=1` becomes `[page - 1]`.
- **The result stays a data expression.** `[page]` picks a page of the query, not an element of an array, so it still loads lazily with `to_a`.
- **One limit per expression.** A second `*`, `/` or range on the same expression raises.
- **A limit without a sort** returns rows in whatever order the database chooses, as in SQL.

### Why precedence works

Ruby binds unary `-`, `[]`, `*` and `/` tighter than `+`, `&` and `^`. So:

- **A limit travels with its sort key.** In `^ -Col[:views] * 10`, Ruby evaluates `-Col[:views] * 10` first, and `^` receives one sort key carrying a limit. No parentheses are needed, except around a page before `[page]`.
- **Inside brackets, a sort applies to that nested table.** In `Users[:username, Posts[:title] ^ -Col[:views] * 3]`, each user gets their own 3 most viewed posts.
- **After `&` and `+`, a sort applies to the whole expression.** `Users[:username] & Posts[:title] ^ Col[:username]` sorts the joined rows, and `Users[] + Posts[] ^ Col[:username]` sorts the users.
- **`<`, `>` and `<=>` bind looser than `^`,** so `Users[] < Posts[] ^ Col[:username]` sorts only `Posts` before joining it, which LowData rejects. Add parentheses, as when mixing any operators: `(Users[] < Posts[]) ^ Col[:username]`.

`Col` is LowData's own class, so LowData decides what `-`, `+`, `*`, `/` and `[]` do on it. With plain symbols and arrays, Ruby's own methods would run first. For example, `^ [:views] * 3` repeats the array three times instead of limiting.

### Where sorts and limits apply

- **Flat joins and `Table[]`:** `ORDER BY` and `LIMIT` go on the single query. Each `Col` column is qualified with the one joined table that has it, as `Table[]` finds column owners. When no table or more than one has it, LowData raises.
- **Nested tables:** each table has its own query, so a sort goes in that query's `ORDER BY`, and grouping keeps the order. A limit, range or page on a nested table applies per parent, using `ROW_NUMBER() OVER (PARTITION BY <link column> ORDER BY ...)`. SQLite 3.25+, PostgreSQL and MySQL 8 support window functions.
- **`+` chains:** `^` and arithmetic after a chain apply to its first table, which is the subject. To sort or limit a nested table, put it in brackets.

### A full example

```ruby
class PostsData < LowData
  # The 10 most viewed published posts.
  def popular
    Posts(published: true)[:title, :views] ^ -Col[:views] * 10
  end

  # Alphabetical, with id breaking ties.
  def alphabetical
    Posts[:title] ^ Col[:title, :id]
  end

  # Newest first, 20 per page, each post with its author and 3 latest comments.
  def feed(page:)
    (
      Posts(published: true)[
        :title,
        :created_at,
        Comments[:body] ^ -Col[:created_at] * 3,
        author: Users[:username]
      ] ^ -Col[:created_at] / 20
    )[page]
  end

  # Users who have posted, alphabetically, each with their 3 most viewed posts.
  def authors
    Users(Posts)[:username, Posts[:title] ^ -Col[:views] * 3] ^ Col[:username]
  end

  # A flat join, sorted across both tables.
  def report
    Users[:username] & Posts[:title, :views] ^ Col[:username] + -Col[:views]
  end
end
```

### Changes to the `expressions` gem

`^`, `*` and `/` need hooks in the `expressions` gem, like the existing operators: `xor_`, `multiply_` and `divide_`, each with `_expression`, `_value` and `_type` variants. LowData implements the `_value` hooks: `^` takes a `Col`, and `*` and `/` take integers. The `_expression` hooks raise for now, which leaves `^` free to mean symmetric difference between data expressions later.

## Options considered

Each was tried against Ruby's parser with `ruby -w`.

### Sort syntax

**Sequel's methods (`.order(Sequel.desc(:views)).limit(10)`).**
- ✅ Every Sequel feature, documented already, and no parentheses.
- ❌ Doesn't read like the rest of LowData. `.order(views: :desc)`, the ActiveRecord habit, silently compiles to `ORDER BY (views = desc)` in Sequel.
- **Outcome:** not now. It may come back as an explicit form for sorts `Col` can't express.

**`sort()` and `limit()` methods with a block (`.sort { views.desc }.limit(20)`).**
- ✅ No parentheses, and multiline chains with leading dots.
- ❌ Ruby's `Enumerable#sort` takes a comparison block, so `sort { views.desc }` looks like something it isn't.

**`^` with a symbol, and `-:views` for descending.**
- ✅ `-views` is the convention of Django, JSON:API and Mongoose.
- ❌ `Symbol` has no unary minus, so it needs a core extension or a refinement in every file. `-Col[...]` gets the same result on LowData's own class.

**Other spellings for descending:**
- `^ '-views'` mixes strings with symbols.
- `^ :views!` borrows `!`, which means something else in Ruby.
- `^ { views: :desc }` is long.
- `^ Desc[:views]` reserves a second name.
- `^ -> { views.desc }` is noisy for the common case.
- `^ 'views desc'` would have to be parsed safely.
- `^ { views: :! }` is cryptic.
- **Binary `-` (`Posts[] - :views`)** binds tighter than `&` and `^`, so it sorts the wrong part of mixed expressions.
- **`|` for descending** has the same precedence as `^`, but `|` doesn't suggest "down" and already means union and `OR`.
- **`!~` for descending** has the lowest precedence of all, but it's non-associative, so it can be used only once and only at the end.

**`^!` for descending.**
- `^! :views` parses as `^ (!:views)`, which is `^ false`, so the column is lost before LowData sees it.
- `^! Col[:views]` works because `Col` can define `!`, but RuboCop rewrites it to `^ !Col[:views]`. It also reads poorly for later columns (`+!` triggers a Ruby warning) and makes `!` stop returning a boolean.
- **Outcome:** rejected as the documented form. It could be added as an alias later.

**`!` or `-` before the whole expression (`-Posts[:title] ^ :views`).** Every column then sorts in the same direction.

**`^[...]` with an array (`Posts[:title] ^[:views]`).** The shortest sort, but the array binds first, so `^[:views] * 3` repeats the array and `^[:views][0...20]` slices it. Both limits disappear silently. `.^[:views]` avoids that but needs the dot.

**Sort markers in square brackets (`Posts[:title, -:views] * 10`).** Short, but it needs `Symbol#-@`, and it brings sorting into the brackets that ADR 0003 limited to columns and nested tables.

**Ruby-flavoured methods:**
- `max_by(10, &:views)` means exactly what Ruby's `max_by` means, but it only covers "top N".
- `order(&:views)` only handles one ascending column.
- `order { [-views, title] }` needs LowData to add unary minus to Sequel's virtual rows.

**Curiosities:**
- `.↑(:views)` and `.↓(:views)` are valid Ruby but can't be typed.
- `order(..:views)` is a range whose direction nobody would remember.
- `order(-2)` sorts by select-list position and breaks when columns move.
- `newest(10)` and `each_slice(1000)` are conveniences rather than syntax, and may come later.

**Names: `Column`, `By` and `Col`.** `Col` is short, reads as a column, and is less likely than `By` to clash with a table name.

### Limit syntax

**Slicing the expression (`(Posts[:title] ^ Col[:views])[...20]`).** `[]` binds tighter than `^`, so the slice needs parentheses every time.

**`^` with a negative limit (`^ :views ^ -10`, like `array.last(10)`).** Short, but it's unclear whether the rows come back ascending, like Ruby's `last`, or descending, like SQL.

**`*` and `/` (chosen).** They continue the arithmetic, precedence places them correctly, and `*` binds tighter than `+`, so `Users[] + Posts[] * 3` limits the nested posts.

## Out of scope

- **Sorting by SQL functions or with `NULLS LAST`.** `Col { lower(title) }` with a Sequel virtual row block is the likely shape.
- **Comparing columns in filters,** e.g. `Posts(updated_at: Col[:created_at])`, which `Col` makes possible.
- **Cursor (keyset) pagination,** e.g. `.after(id: 42)`.
- **A `!` alias for `-` on `Col`.**

## Consequences

- Queries read left to right as arithmetic: rows `( )`, conditions `{ }`, columns `[ ]`, order `^ Col[ ]`, and amounts `* /`.
- `Col` is reserved like `Table`, so a table called `col` needs another name.
- `*` meaning "limit" and `/` meaning "pages" have to be learned. The README needs to explain them.
- Limits on nested tables need window functions, so they need SQLite 3.25+, PostgreSQL or MySQL 8.
- The `expressions` gem gains `^`, `*` and `/`, and needs a new release.
