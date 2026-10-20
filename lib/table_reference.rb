# frozen_string_literal: true

class LowData
  # A table named by a constant, such as `Users`, waiting for its columns: `Users[:username]`.
  # An inverted reference is `Table`, standing in for the repository's table and any table related to it.
  class TableReference
    attr_reader :table

    def initialize(table:, inverted: false)
      @table = table
      @inverted = inverted
    end

    # Each argument's type decides its meaning:
    #   Posts[:title]                              # A symbol is a column. No columns selects every column.
    #   Users[:username, Posts[:title]]            # A data expression is a nested table.
    #   Reviews[:rating, author: Users[:username]] # A keyword with a data expression names a nested table.
    #   Posts[:title, published: true]             # A keyword with any other value is a filter.
    def [](*arguments, **keywords)
      return inverted(arguments:, keywords:) if @inverted

      expressions, columns = arguments.partition { |argument| argument.is_a?(DataExpression) }
      check_columns!(columns:)
      named, filters = keywords.partition { |_key, value| value.is_a?(DataExpression) }
      nested = expressions.map { |expression| [nil, expression] } + named

      DataExpression.new(node: DataExpression::Source.new(table:, columns:, nested: nested(pairs: nested), filters: filters.to_h))
    end

    private

    def nested(pairs:)
      pairs.map { |key, expression| DataExpression::Nested.new(key:, node: expression.node) }
    end

    def inverted(arguments:, keywords:)
      check_columns!(columns: arguments)
      raise ArgumentError, 'Table[] takes column names only' if keywords.any?

      DataExpression.new(node: DataExpression::Inversion.new(table:, columns: arguments))
    end

    def check_columns!(columns:)
      invalid = columns.reject { |column| column.is_a?(Symbol) }
      raise ArgumentError, "Columns are symbols, e.g. Posts[:title], not #{invalid.map(&:inspect).join(', ')}" if invalid.any?
    end
  end
end
