# frozen_string_literal: true

class LowData
  # Compiles a DataExpression join tree into a Sequel dataset, inferring each join's ON clause from foreign keys.
  class QueryCompiler
    INVERSION_JOIN_MESSAGE = "Table[] can't be joined with other expressions"
    NESTING_JOIN_MESSAGE = 'Nested tables return nested data, so + and tables nested in brackets can\'t be combined with &, <, > or <=>'
    ORDERED_JOIN_MESSAGE = 'Sort and limit after joining, e.g. (Users[] < Posts[]) ^ Col[:username]. Ruby binds ^ tighter ' \
                           'than <, > and <=>, and * and / tighter than every join, so add parentheses around the join'

    def initialize(database:)
      raise ConfigError, ConfigError::MISSING_DATABASE if database.nil?

      @database = database
      @schema = Schema.new(database:)
      @filters = FilterCompiler.new(database:, schema: @schema)
      @orders = OrderCompiler.new(schema: @schema)
    end

    def compile(node:)
      return compile_ordered(node:) if node.is_a?(DataExpression::Ordered)

      compile_unordered(node:, sources: [])
    end

    private

    # Sort keys and rows apply to the whole query, so each sort column can belong to any joined table.
    def compile_ordered(node:)
      sources = []
      dataset = compile_unordered(node: node.node, sources:)
      @orders.apply(dataset:, keys: node.keys, rows: node.rows, tables: sources.map(&:table))
    end

    def compile_unordered(node:, sources:)
      return compile_inversion(node:, sources:) if node.is_a?(DataExpression::Inversion)

      dataset = filter(dataset: build(node:, sources:), sources:)
      dataset.select(*sources.flat_map { |source| selections(source:) })
    end

    def compile_inversion(node:, sources:)
      tree, selections = Inversion.new(schema: @schema).resolve(node:)
      filter(dataset: build(node: tree, sources:), sources:).select(*selections)
    end

    def build(node:, sources:)
      raise JoinError, INVERSION_JOIN_MESSAGE if node.is_a?(DataExpression::Inversion)
      raise JoinError, ORDERED_JOIN_MESSAGE if node.is_a?(DataExpression::Ordered)
      return source_dataset(source: node, sources:) if node.is_a?(DataExpression::Source)
      raise JoinError, NESTING_JOIN_MESSAGE if nesting?(node:) || nesting?(node: node.right)

      raise JoinError, nested_join_message if node.right.is_a?(DataExpression::Join)

      join_dataset(dataset: build(node: node.left, sources:), type: node.type, right: node.right, sources:)
    end

    def join_dataset(dataset:, type:, right:, sources:)
      raise JoinError, INVERSION_JOIN_MESSAGE if right.is_a?(DataExpression::Inversion)
      raise JoinError, ORDERED_JOIN_MESSAGE if right.is_a?(DataExpression::Ordered)
      raise JoinError, NESTING_JOIN_MESSAGE if right.nested.any?
      raise JoinError, "Can't join #{right.table} to itself" if sources.any? { |source| source.table == right.table }

      conditions = join_conditions(left_tables: sources.map(&:table), right_table: right.table)
      sources << right
      dataset.join_table(type, right.table, conditions)
    end

    def nesting?(node:)
      node.is_a?(DataExpression::Join) && node.type == :nest
    end

    def source_dataset(source:, sources:)
      raise JoinError, NESTING_JOIN_MESSAGE if source.nested.any?

      sources << source
      @database[source.table]
    end

    # Every table's filters go in the WHERE clause, so they apply to the joined rows.
    def filter(dataset:, sources:)
      sources.reduce(dataset) { |filtered, source| @filters.apply(dataset: filtered, source:) }
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
