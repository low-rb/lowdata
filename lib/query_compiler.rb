# frozen_string_literal: true

class LowData
  # Compiles a DataExpression join tree into a Sequel dataset, inferring each join's ON clause from foreign keys.
  class QueryCompiler
    INVERSION_JOIN_MESSAGE = "Table[] can't be joined with other expressions"
    NESTING_JOIN_MESSAGE = 'Nested tables return nested data, so + and tables nested in brackets can\'t be combined with &, <, > ' \
                           'or <=>. Nest the join instead, e.g. Users[:username] + (Posts[:title] & Comments[:body])'
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

      conditions = join_conditions(left: sources, right:)
      sources << right
      dataset.join_table(type, right.table, conditions)
    end

    def nesting?(node:)
      node.is_a?(DataExpression::Join) && node.nest?
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
      return [Sequel[source.table].*] if source.every_column?

      @schema.check_renames!(table: source.table, renames: source.renames)
      source.columns.map { |column| Sequel[source.table][column] } + source.aliases
    end

    # Each table joins to the table before it, or to an earlier one by a foreign key named in round brackets, so foreign
    # keys between other tables can't change or break a join.
    def join_conditions(left:, right:)
      named = left.flat_map { |source| references(from: right, to: source, named: true) + references(from: source, to: right, named: true) }
      candidates = named.any? ? named : references(from: right, to: left.last) + references(from: left.last, to: right)
      raise JoinError, unlinked_join_message(left:, right:) if candidates.empty?
      raise JoinError, "More than one foreign key links #{right.table} to #{left.last.table}" if candidates.length > 1

      candidates.first
    end

    def references(from:, to:, named: false)
      @schema.references(from: from.table, to: to.table, named: named ? from.filter.foreign_keys : nil)
    end

    def unlinked_join_message(left:, right:)
      message = "No foreign key links #{right.table} to #{left.last.table}, the table before it"
      choices = left[0...-1].flat_map do |source|
        [[right.table, source.table], [source.table, right.table]].flat_map do |from, to|
          @schema.links(from:, to:).map { |link| "#{LowData.constant_name(from)}(:#{link[:columns].first})" }
        end
      end
      choices.empty? ? message : "#{message}. To join it to an earlier table, name the foreign key: #{choices.sort.join(' or ')}"
    end

    def nested_join_message
      'Ruby evaluated a join on the right first, e.g. `Users[] < Posts[] & Comments[]` runs `Posts[] & Comments[]` first ' \
        'because & binds tighter than <. Add parentheses to join from the left: `(Users[] < Posts[]) & Comments[]`'
    end
  end
end
