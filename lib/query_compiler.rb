# frozen_string_literal: true

class LowData
  # Compiles a DataExpression join tree into a Sequel dataset, inferring each join's ON clause from foreign keys.
  class QueryCompiler
    INVERSION_JOIN_MESSAGE = "Table[] can't be joined with other expressions"

    def initialize(database:)
      raise ConfigError, 'Set LowData.database to a Sequel database, e.g. LowData.database = Sequel.sqlite' if database.nil?

      @database = database
      @schema = Schema.new(database:)
    end

    def compile(node:)
      return compile_inversion(node:) if node.is_a?(DataExpression::Inversion)

      sources = []
      dataset = build(node:, sources:)
      dataset.select(*sources.flat_map { |source| selections(source:) })
    end

    private

    def compile_inversion(node:)
      tree, selections = Inversion.new(schema: @schema).resolve(node:)
      build(node: tree, sources: []).select(*selections)
    end

    def build(node:, sources:)
      raise JoinError, INVERSION_JOIN_MESSAGE if node.is_a?(DataExpression::Inversion)
      return source_dataset(source: node, sources:) if node.is_a?(DataExpression::Source)

      raise JoinError, nested_join_message if node.right.is_a?(DataExpression::Join)

      join_dataset(dataset: build(node: node.left, sources:), type: node.type, right: node.right, sources:)
    end

    def join_dataset(dataset:, type:, right:, sources:)
      raise JoinError, INVERSION_JOIN_MESSAGE if right.is_a?(DataExpression::Inversion)
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
        @schema.references(from: right_table, to: left_table) + @schema.references(from: left_table, to: right_table)
      end

      raise JoinError, "No foreign key links #{right_table} to #{left_tables.join(', ')}" if candidates.empty?
      raise JoinError, "More than one foreign key links #{right_table} to #{left_tables.join(', ')}" if candidates.length > 1

      candidates.first
    end

    def nested_join_message
      'Ruby evaluated a join on the right first, e.g. `Users[] < Posts[] & Comments[]` runs `Posts[] & Comments[]` first ' \
        'because & binds tighter than <. Add parentheses to join from the left: `(Users[] < Posts[]) & Comments[]`'
    end
  end
end
