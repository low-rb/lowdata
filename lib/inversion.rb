# frozen_string_literal: true

class LowData
  # Resolves `Table[:username, :title]` in PostsData to a join tree: posts left joined to each related table that owns a column.
  class Inversion
    def initialize(schema:)
      @schema = schema
    end

    # Returns the join tree and the columns to select, in the order they were asked for, then the renamed columns.
    def resolve(node:)
      owned = node.columns.map { |column| [owner(table: node.table, column:), column, nil] } +
              node.renames.map { |name, column| [renamed_owner(table: node.table, name:, column:), column, name] }
      selections = owned.map { |table, column, name| name ? Sequel[table][column].as(name) : Sequel[table][column] }

      [tree(node:, tables: owned.map(&:first)), selections]
    end

    private

    def owner(table:, column:)
      owners = owners(table:, column:)
      raise JoinError, "No table related to #{table} has a #{column} column" if owners.empty?
      raise JoinError, ambiguous_message(table:, column:, owners:) if owners.length > 1

      owners.first
    end

    def owners(table:, column:)
      return [table] if @schema.columns(table:).include?(column)

      @schema.related_tables(table:).select { |related| @schema.columns(table: related).include?(column) }
    end

    # The owner of a renamed column, which mustn't also have a column with the new name.
    def renamed_owner(table:, name:, column:)
      if owners(table:, column:).empty? && owners(table:, column: name).any?
        raise ArgumentError, "No table related to #{table} has a #{column} column. To rename #{name}, write #{column}: :#{name}"
      end

      owner(table:, column:).tap { |owner| @schema.check_renames!(table: owner, renames: { name => column }) }
    end

    # The repository's table left joined to each other table that owns a column. Joins link to the table before them,
    # so each table names the foreign keys that link it to the repository's table, on whichever side they are.
    def tree(node:, tables:)
      owners = tables.uniq - [node.table]
      base_keys = owners.flat_map { |table| link_columns(from: node.table, to: table) }
      base = DataExpression::Source.new(table: node.table, columns: [], filter: node.filter.merge(named(base_keys)))

      owners.reduce(base) do |left, table|
        right = DataExpression::Source.new(table:, columns: [], filter: named(link_columns(from: table, to: node.table)))
        DataExpression::Join.new(type: :left, left:, right:)
      end
    end

    def link_columns(from:, to:)
      @schema.links(from:, to:).flat_map { |link| link[:columns] }
    end

    def named(foreign_keys)
      DataExpression::Filter.new(foreign_keys:)
    end

    def ambiguous_message(table:, column:, owners:)
      "#{owners.join(' and ')} both have a #{column} column and are related to #{table}. " \
        "Join explicitly instead, e.g. #{LowData.constant_name(table)}[] < #{LowData.constant_name(owners.first)}[:#{column}]"
    end
  end
end
