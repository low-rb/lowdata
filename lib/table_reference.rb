# frozen_string_literal: true

class LowData
  # A table named by a constant, such as `Users`, waiting for its columns: `Users[:username]`.
  class TableReference
    attr_reader :table

    def initialize(table:)
      @table = table
    end

    # No columns selects every column: `Users[]`.
    def [](*columns)
      DataExpression.new(table:, columns:)
    end
  end
end
