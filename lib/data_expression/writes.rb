# frozen_string_literal: true

class LowData
  class DataExpression < ::Expressions::Expression
    # Writes through a table in square brackets, which choose the columns returned. See Writer:
    #   Posts[:id, :created_at] << { title: 'Hello' }      # Inserts, returning the new row's id and created_at.
    #   Posts(slug: 'hello')[:id] <= { title: 'Hello' }    # Upserts, returning the row's id.
    module Writes
      # It runs straight away and returns the rows, so it overrides the expressions gem's `<=`, which builds a copy.
      def <=(rows)
        Writer.new(database: LowData.database).upsert(source: write_source(operator: '<='), rows:)
      end

      def delete
        raise ArgumentError, 'Square brackets choose columns, and a delete removes whole rows. Delete from the table, e.g. ' \
                             'Posts(id: 1).delete'
      end

      private

      # Writes go to one table.
      def write_source(operator:)
        return @node if @node.is_a?(Source) && @node.nested.empty?

        raise ArgumentError, "#{operator} writes to one table, e.g. Posts[:id] #{operator} { title: 'Hello' }, not to joined, " \
                             'nested or sorted tables'
      end

      # The expressions gem's `<<` calls this on the expression itself and returns what it returns, the inserted rows.
      def append_value(rows)
        Writer.new(database: LowData.database).insert(source: write_source(operator: '<<'), rows:)
      end

      def append_expression(_expression)
        raise ArgumentError, WriteChecks::EXPRESSION_MESSAGES.fetch('<<')
      end

      def append_type(type_)
        raise ArgumentError, "<< inserts rows, e.g. Posts << { title: 'Hello' }, not the type #{type_}"
      end
    end

    include Writes
  end
end
