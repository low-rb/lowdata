# frozen_string_literal: true

class LowData
  # Joins tables with operators and builds a join tree for QueryCompiler:
  #   Users[:username, Posts[:title]]   # Nested; every user once, with their posts nested. See Nesting.
  #   Users[:username] + Posts[:title]   # Nested, shorthand for the above.
  #   Users[:username] & Posts[:title]   # Inner join.
  #   Users[:username] < Posts[:title]   # Left join.
  #   Users[:username] > Posts[:title]   # Right join.
  #   Users[:username] <=> Posts[:title] # Full outer join.
  #   Table[:username, :title]           # Inverted; the repository's table joined to whichever tables own the columns.
  # And sorts and limits the result. See Col and Rows:
  #   Posts[:title] ^ -Col[:views] * 10  # ORDER BY views DESC LIMIT 10
  #   (Posts[:title] / 20)[2]            # LIMIT 20 OFFSET 40
  class DataExpression < ::Expressions::Expression
    # The filters in a table's round brackets: `Posts(published: true) { views > 100 }`. See FilterCompiler.
    # `foreign_keys` aren't filters: they name the foreign key a nested join links by, `Posts(:user_id)`. See NestedJoin.
    Filter = ::Data.define(:values, :conditions, :related, :foreign_keys) do
      def initialize(values: {}, conditions: [], related: [], foreign_keys: [])
        super
      end

      def merge(other)
        with(values: values.merge(other.values), conditions: conditions + other.conditions, related: related + other.related,
             foreign_keys: foreign_keys + other.foreign_keys)
      end
    end
    # A table in another table's round brackets, keeping rows with `count` related rows: `Users(Posts => 3..)`.
    Related = ::Data.define(:key, :source, :count)
    # A table with the columns to select, the columns renamed (`headline: :title`), the tables nested in its brackets and
    # the filter on its rows.
    Source = ::Data.define(:table, :columns, :renames, :nested, :filter) do
      def initialize(table:, columns:, renames: {}, nested: [], filter: Filter.new)
        super
      end
    end

    class Source
      # No columns or renames selects every column.
      def every_column? = columns.empty? && renames.empty?

      # The keys of each row, as asked for.
      def names = columns + renames.keys

      # The renamed columns, as `posts.title AS headline`.
      def aliases = renames.map { |name, column| Sequel[table][column].as(name) }
    end
    # A table nested in another table's brackets, under an optional key: `Reviews[:rating, author: Users[:username]]`.
    Nested = ::Data.define(:key, :node)
    Join = ::Data.define(:type, :left, :right) do
      def nest? = type == :nest
    end
    # Tables nested side by side in the table before them: `Posts[:title] + [Comments[:body], Likes[]]`.
    Siblings = ::Data.define(:nodes)
    Inversion = ::Data.define(:table, :columns, :renames, :filter)
    # A node sorted by `keys` (Col::Key) with `rows` (Rows) kept: `Posts[:title] ^ -Col[:views] * 10`.
    Ordered = ::Data.define(:node, :keys, :rows)

    JOIN_HOOKS = { add: :nest, intersect: :inner, lt: :left, gt: :right, compare: :full }.freeze

    attr_reader :node

    def initialize(node:)
      @node = node
    end

    SORT_MESSAGE = 'Sort by columns with Col[], e.g. Posts[:title] ^ Col[:views], not %<value>s'
    NESTED_DATASET_MESSAGE = 'Nested tables load with one query per table, so they have no single dataset. Call sql to see ' \
                             'each query, or to_a to load them'
    def dataset(database: LowData.database)
      raise Error, NESTED_DATASET_MESSAGE if nested?

      QueryCompiler.new(database:).compile(node: @node)
    end

    # Nested tables load with one query per table, so their SQL is each query, separated by semicolons.
    def sql(database: LowData.database)
      return Nesting.new(database:).sql(node: @node).join(";\n") if nested?

      dataset(database:).sql
    end

    def to_a(database: LowData.database)
      return Nesting.new(database:).load(node: @node) if nested?

      dataset(database:).all
    end

    # Picks a page after splitting rows into pages: `(Posts[:title] / 20)[2]` is the third page of 20. Returns a new
    # expression, so the same pages can be picked from more than once.
    def [](page)
      ordered = @node if @node.is_a?(Ordered)
      raise ArgumentError, 'Split rows into pages before picking one, e.g. (Posts[:title] / 20)[0]' unless ordered&.rows

      DataExpression.new(node: ordered.with(rows: ordered.rows.page(page)))
    end

    private

    def nested?
      node = @node.is_a?(Ordered) ? @node.node : @node
      (node.is_a?(Join) && node.nest?) || (node.is_a?(Source) && node.nested.any?)
    end

    # Sorting again adds sort keys after the existing ones, and an expression keeps one limit, range or page size.
    def order(keys:, rows:)
      ordered = @node.is_a?(Ordered) ? @node : Ordered.new(node: @node, keys: [], rows: nil)
      @node = ordered.with(keys: ordered.keys + keys, rows: Rows.merge(ordered.rows, rows))
    end

    def add_siblings(expressions)
      invalid = expressions.reject { |expression| expression.is_a?(DataExpression) }
      raise ArgumentError, "Nest data expressions such as Comments[:body], not #{invalid.map(&:inspect).join(', ')}" if invalid.any?
      raise ArgumentError, 'Nest at least one table, e.g. Posts[:title] + [Comments[:body], Likes[]]' if expressions.empty?

      @node = Join.new(type: :nest, left: @node, right: Siblings.new(nodes: expressions.map(&:node)))
    end

    def xor_value(value)
      raise ArgumentError, format(SORT_MESSAGE, value: value.inspect) unless value.is_a?(Col)

      order(keys: value.keys, rows: value.rows)
    end

    def multiply_value(count)
      order(keys: [], rows: Rows.limit(count))
    end

    def divide_value(size)
      order(keys: [], rows: Rows.pages(size))
    end

    def xor_expression(_expression)
      raise ArgumentError, format(SORT_MESSAGE, value: 'a data expression')
    end

    def xor_type(type_)
      raise ArgumentError, format(SORT_MESSAGE, value: type_)
    end

    { multiply: 'Limit', divide: 'Split into pages' }.each do |prefix, action|
      define_method(:"#{prefix}_expression") do |_expression|
        raise ArgumentError, "#{action} by a positive integer, not a data expression"
      end

      define_method(:"#{prefix}_type") do |type_|
        raise ArgumentError, "#{action} by a positive integer, not the type #{type_}"
      end
    end

    JOIN_HOOKS.each do |prefix, type|
      define_method(:"#{prefix}_expression") do |expression|
        @node = Join.new(type:, left: @node, right: expression.node)
      end

      define_method(:"#{prefix}_value") do |value|
        return add_siblings(value) if prefix == :add && value.is_a?(Array)

        raise ArgumentError, "Join a data expression such as Posts[:title], not the value #{value.inspect}"
      end

      define_method(:"#{prefix}_type") do |type_|
        raise ArgumentError, "Join a data expression such as Posts[:title], not the type #{type_}"
      end
    end
  end
end
