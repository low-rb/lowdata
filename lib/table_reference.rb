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

    # No columns selects every column: `Users[]`.
    def [](*columns)
      node = @inverted ? DataExpression::Inversion.new(table:, columns:) : DataExpression::Source.new(table:, columns:)
      DataExpression.new(node:)
    end
  end
end
