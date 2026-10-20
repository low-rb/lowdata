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
  class DataExpression < ::Expressions::Expression
    # A table with the columns to select, the tables nested in its brackets and the filters on its rows.
    Source = ::Data.define(:table, :columns, :nested, :filters) do
      def initialize(table:, columns:, nested: [], filters: {})
        super
      end
    end
    # A table nested in another table's brackets, under an optional key: `Reviews[:rating, author: Users[:username]]`.
    Nested = ::Data.define(:key, :node)
    Join = ::Data.define(:type, :left, :right)
    Inversion = ::Data.define(:table, :columns)

    JOIN_HOOKS = { add: :nest, intersect: :inner, lt: :left, gt: :right, compare: :full }.freeze

    attr_reader :node

    def initialize(node:)
      @node = node
    end

    NESTED_SQL_MESSAGE = '+ loads nested data with one query per table, so it has no single SQL query. Call to_a instead'

    def dataset(database: LowData.database)
      raise Error, NESTED_SQL_MESSAGE if nested?

      QueryCompiler.new(database:).compile(node: @node)
    end

    def sql(database: LowData.database)
      dataset(database:).sql
    end

    def to_a(database: LowData.database)
      return Nesting.new(database:).load(node: @node) if nested?

      dataset(database:).all
    end

    private

    def nested?
      (@node.is_a?(Join) && @node.type == :nest) || (@node.is_a?(Source) && @node.nested.any?)
    end

    JOIN_HOOKS.each do |prefix, type|
      define_method(:"#{prefix}_expression") do |expression|
        @node = Join.new(type:, left: @node, right: expression.node)
      end

      define_method(:"#{prefix}_value") do |value|
        raise ArgumentError, "Join a data expression such as Posts[:title], not the value #{value.inspect}"
      end

      define_method(:"#{prefix}_type") do |type_|
        raise ArgumentError, "Join a data expression such as Posts[:title], not the type #{type_}"
      end
    end
  end
end
