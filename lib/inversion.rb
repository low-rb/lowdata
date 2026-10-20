# frozen_string_literal: true

class LowData
  # Resolves `Table[:username, :title]` in PostsData to a join tree: posts left joined to each related table that owns a column.
  class Inversion
    def initialize(schema:)
      @schema = schema
    end

    # Returns the join tree and the columns to select, in the order they were asked for.
    def resolve(node:)
      owners = node.columns.to_h { |column| [column, owner(table: node.table, column:)] }
      base = DataExpression::Source.new(table: node.table, columns: [])

      tree = (owners.values.uniq - [node.table]).reduce(base) do |left, table|
        DataExpression::Join.new(type: :left, left:, right: DataExpression::Source.new(table:, columns: []))
      end

      [tree, owners.map { |column, table| Sequel[table][column] }]
    end

    private

    def owner(table:, column:)
      return table if @schema.columns(table:).include?(column)

      owners = @schema.related_tables(table:).select { |related| @schema.columns(table: related).include?(column) }
      raise JoinError, "No table related to #{table} has a #{column} column" if owners.empty?
      raise JoinError, ambiguous_message(table:, column:, owners:) if owners.length > 1

      owners.first
    end

    def ambiguous_message(table:, column:, owners:)
      "#{owners.join(' and ')} both have a #{column} column and are related to #{table}. " \
        "Join explicitly instead, e.g. #{LowData.constant_name(table)}[] < #{LowData.constant_name(owners.first)}[:#{column}]"
    end
  end
end
