# frozen_string_literal: true

class LowData
  # Loads nested data, one query per table. Tables nest explicitly in brackets, or by inference with +:
  #   Posts[:title, Users[:username]]  # => [{ title: 'Hello', user: { username: 'alice' } }]
  #   Users[:username] + Posts[:title] # => [{ username: 'alice', posts: [{ title: 'Hello' }] }]
  # In a + chain the first table is the subject, and each other operand nests under the table its foreign key links it to.
  # A join nests as flat rows, loaded with one query, and tables can nest under each of its rows: see NestedJoin.
  class Nesting
    # A table in the nesting tree. `link` connects it to its parent node: `parent_column` on the parent's rows matches
    # `child_column` on this table's rows, and `many` nests the matches as an array rather than one object.
    # `keys` and `rows` sort and limit the table's rows, per parent when it's nested. `source` is a table or a NestedJoin.
    Node = ::Data.define(:source, :key, :link, :children, :keys, :rows) do
      def initialize(source:, key:, link:, children:, keys: [], rows: nil)
        super
      end
    end

    class Node
      def join
        source if source.is_a?(NestedJoin)
      end

      def tables
        join ? join.tables : [source.table]
      end
    end
    # `parent_table` is set when the parent is a join, whose rows hold `parent_column` under `parent_key`.
    Link = ::Data.define(:parent_column, :child_column, :many, :parent_table) do
      def initialize(parent_column:, child_column:, many:, parent_table: nil)
        super
      end

      def parent_key
        parent_table ? :"lowdata_#{parent_table}_#{parent_column}" : parent_column
      end
    end

    ROW_NUMBER = :lowdata_row_number
    # Stands in for the parent values a nested table's query is filtered by, which aren't known until the parents load.
    PARENT_VALUES = Sequel.lit('(...)')
    # A nested join's link value, selected under its own name so it can't clash with the joined columns.
    LINK = :lowdata_link

    def initialize(database:)
      raise ConfigError, ConfigError::MISSING_DATABASE if database.nil?

      @database = database
      @schema = Schema.new(database:)
      @filters = FilterCompiler.new(database:, schema: @schema)
      @orders = OrderCompiler.new(schema: @schema)
      @queries = QueryCompiler.new(database:)
    end

    def load(node:)
      root = NestingTree.new(schema: @schema).build(node:)
      shape(node: root, rows: dataset(node: root).all)
    end

    # The SQL of each query `load` runs, parents first, without running them. A nested table's query shows the parent
    # values it's filtered by as `IN (...)`.
    def sql(node:)
      queries(node: NestingTree.new(schema: @schema).build(node:)).map(&:sql)
    end

    private

    def queries(node:, values: nil)
      [dataset(node:, values:), *node.children.flat_map { |child| queries(node: child, values: PARENT_VALUES) }]
    end

    # A node's rows, or when it's nested, its rows linked to the parents' `values`.
    def dataset(node:, values: nil)
      dataset = node.join ? join_dataset(node:) : table_dataset(node:)
      dataset = dataset.where(Sequel::SQL::BooleanExpression.new(:IN, link_column(node:), values)) if values
      return per_parent(node:, dataset:) if values && node.rows

      @orders.apply(dataset:, keys: node.keys, rows: node.rows, tables: node.tables)
    end

    def table_dataset(node:)
      @schema.check_renames!(table: node.source.table, renames: node.source.renames)
      @filters.apply(dataset: @database[node.source.table].select(*select_columns(node:)), source: node.source)
    end

    # A join's rows, with the columns its parent and children link by selected under LINK and each Link#parent_key.
    def join_dataset(node:)
      parents = node.children.map { |child| Sequel[child.link.parent_table][child.link.parent_column].as(child.link.parent_key) }
      links = node.link ? [link_column(node:).as(LINK)] : []
      @queries.compile(node: node.join.node).select_append(*parents.uniq, *links)
    end

    def link_column(node:)
      node.join ? Sequel[node.source.table][node.link.child_column] : node.link.child_column
    end

    # Keeps each parent's rows, e.g. each user's 3 most viewed posts, by numbering the rows within each parent.
    def per_parent(node:, dataset:)
      numbered = dataset.select_append(row_number(node:).as(ROW_NUMBER))
      @database.from(numbered).where(ROW_NUMBER => row_numbers(rows: node.rows)).order(ROW_NUMBER)
    end

    def row_number(node:)
      order = @orders.order(keys: node.keys, tables: node.tables)
      Sequel.function(:row_number).over(partition: Sequel[node.source.table][node.link.child_column], order: order.empty? ? nil : order)
    end

    # Row numbers start at 1, and rows count from 0.
    def row_numbers(rows:)
      @orders.check_rows!(rows:)
      first = rows.offset + 1
      rows.limit ? first..(rows.offset + rows.limit) : (first..)
    end

    # The columns asked for, plus the columns each link needs.
    def select_columns(node:)
      source = node.source
      return [Sequel[source.table].*] if source.every_column?

      link_columns = [node.link&.child_column, *node.children.map { |child| child.link.parent_column }].compact
      (source.columns + link_columns).uniq + source.aliases
    end

    # Turns fetched rows into output hashes: the columns asked for, plus each child nested under its key.
    def shape(node:, rows:)
      nested = node.children.to_h { |child| [child, nested_rows(child:, rows:)] }

      rows.map do |row|
        output = columns(node:, row:)
        node.children.each { |child| output[child.key] = matches(child:, row:, nested: nested[child]) }
        output
      end
    end

    def columns(node:, row:)
      return row.except(LINK, ROW_NUMBER, *node.children.map { |child| child.link.parent_key }) if node.join

      node.source.every_column? ? row.except(ROW_NUMBER) : row.slice(*node.source.names)
    end

    def matches(child:, row:, nested:)
      matches = nested.fetch(row[child.link.parent_key], [])
      child.link.many ? matches : matches.first
    end

    # Fetches a child's rows for all parent rows in one query, grouped by the value that links them.
    def nested_rows(child:, rows:)
      values = rows.map { |row| row[child.link.parent_key] }.compact.uniq
      return {} if values.empty?

      child_rows = dataset(node: child, values:).all
      link_column = child.join ? LINK : child.link.child_column
      child_rows.zip(shape(node: child, rows: child_rows))
                .group_by { |row, _output| row[link_column] }
                .transform_values { |pairs| pairs.map(&:last) }
    end
  end
end
