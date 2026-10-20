# frozen_string_literal: true

class LowData
  # Compiles a DataExpression join tree into a Sequel dataset, inferring each join's ON clause from foreign keys.
  class QueryCompiler
    def initialize(database:)
      raise ConfigError, 'Set LowData.database to a Sequel database, e.g. LowData.database = Sequel.sqlite' if database.nil?

      @database = database
      @foreign_keys = {}
    end

    def compile(node:)
      sources = []
      dataset = build(node:, sources:)
      dataset.select(*sources.flat_map { |source| selections(source:) })
    end

    private

    def build(node:, sources:)
      return source_dataset(source: node, sources:) if node.is_a?(DataExpression::Source)

      raise JoinError, nested_join_message if node.right.is_a?(DataExpression::Join)

      join_dataset(dataset: build(node: node.left, sources:), type: node.type, right: node.right, sources:)
    end

    def join_dataset(dataset:, type:, right:, sources:)
      raise JoinError, "Can't join #{right.table} to itself" if sources.any? { |source| source.table == right.table }

      conditions = join_conditions(left_tables: sources.map(&:table), right_table: right.table)
      sources << right
      dataset.join_table(type, right.table, conditions)
    end

    def source_dataset(source:, sources:)
      sources << source
      @database[source.table]
    end

    def selections(source:)
      return [Sequel[source.table].*] if source.columns.empty?

      source.columns.map { |column| Sequel[source.table][column] }
    end

    def join_conditions(left_tables:, right_table:)
      candidates = left_tables.flat_map do |left_table|
        references(from: right_table, to: left_table) + references(from: left_table, to: right_table)
      end

      raise JoinError, "No foreign key links #{right_table} to #{left_tables.join(', ')}" if candidates.empty?
      raise JoinError, "More than one foreign key links #{right_table} to #{left_tables.join(', ')}" if candidates.length > 1

      candidates.first
    end

    # Foreign keys on the `from` table that reference the `to` table, as join conditions.
    def references(from:, to:)
      foreign_keys(table: from).select { |foreign_key| foreign_key[:table] == to }.map do |foreign_key|
        keys = foreign_key[:key] || primary_key(table: to)
        foreign_key[:columns].zip(keys).to_h { |column, key| [Sequel[from][column], Sequel[to][key]] }
      end
    end

    def foreign_keys(table:)
      @foreign_keys[table] ||= @database.foreign_key_list(table)
    end

    def primary_key(table:)
      @database.schema(table).select { |_column, info| info[:primary_key] }.map(&:first)
    end

    def nested_join_message
      'Ruby evaluated a join on the right first, e.g. `Users[] < Posts[] & Comments[]` runs `Posts[] & Comments[]` first ' \
        'because & binds tighter than <. Add parentheses to join from the left: `(Users[] < Posts[]) & Comments[]`'
    end
  end
end
