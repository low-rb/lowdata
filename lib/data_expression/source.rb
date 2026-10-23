# frozen_string_literal: true

class LowData
  class DataExpression < ::Expressions::Expression
    # A table with the columns to select, the columns renamed (`headline: :title`), the tables nested in its brackets and
    # the filter on its rows. `bare` is a table without brackets, `Posts`, which selects every column. See ADR 0006.
    Source = ::Data.define(:table, :columns, :renames, :nested, :filter, :bare) do
      def initialize(table:, columns:, renames: {}, nested: [], filter: Filter.new, bare: false)
        super
      end
    end

    class Source
      # A bare table, `Posts`, selects every column.
      def every_column? = bare

      # Empty brackets, `Posts[]`, select no columns.
      def no_columns? = !bare && columns.empty? && renames.empty?

      # The keys of each row, as asked for.
      def names = columns + renames.keys

      # The renamed columns, as `posts.title AS headline`.
      def aliases = renames.map { |name, column| Sequel[table][column].as(name) }
    end
  end
end
