# frozen_string_literal: true

class LowData
  # Loads nested data, one query per table. Tables nest explicitly in brackets, or by inference with +:
  #   Posts[:title, Users[:username]]  # => [{ title: 'Hello', user: { username: 'alice' } }]
  #   Users[:username] + Posts[:title] # => [{ username: 'alice', posts: [{ title: 'Hello' }] }]
  # In a + chain the first table is the subject, and each other operand nests under the table its foreign key links it to.
  # A join nests as flat rows, loaded with one query: see NestedJoin.
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
    Link = ::Data.define(:parent_column, :child_column, :many)

    ROW_NUMBER = :lowdata_row_number
    # A joined row's link value, selected under its own name so it can't clash with the joined columns.
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
      shape(node: root, rows: fetch(node: root))
    end

    private

    def fetch(node:, filter: nil)
      dataset = @filters.apply(dataset: @database[node.source.table].select(*select_columns(node:)), source: node.source)
      dataset = dataset.where(filter) if filter
      return per_parent(node:, dataset:) if filter && node.rows

      @orders.apply(dataset:, keys: node.keys, rows: node.rows, tables: [node.source.table]).all
    end

    # Loads a nested join's rows for every parent row in one query, with each row's link value under LINK.
    def fetch_join(node:, values:)
      column = Sequel[node.source.table][node.link.child_column]
      dataset = @queries.compile(node: node.join.node).select_append(column.as(LINK)).where(column => values)
      return per_parent(node:, dataset:) if node.rows

      @orders.apply(dataset:, keys: node.keys, rows: node.rows, tables: node.tables).all
    end

    # Keeps each parent's rows, e.g. each user's 3 most viewed posts, by numbering the rows within each parent.
    def per_parent(node:, dataset:)
      numbered = dataset.select_append(row_number(node:).as(ROW_NUMBER))
      @database.from(numbered).where(ROW_NUMBER => row_numbers(rows: node.rows)).order(ROW_NUMBER)
               .all.map { |row| row.except(ROW_NUMBER) }
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
      return [Sequel[node.source.table].*] if node.source.columns.empty?

      link_columns = [node.link&.child_column, *node.children.map { |child| child.link.parent_column }].compact
      (node.source.columns + link_columns).uniq
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

    def fetch_nested(child:, values:)
      return fetch_join(node: child, values:) if child.join

      fetch(node: child, filter: { child.link.child_column => values })
    end

    def columns(node:, row:)
      return row.except(LINK) if node.join

      node.source.columns.empty? ? row.dup : row.slice(*node.source.columns)
    end

    def matches(child:, row:, nested:)
      matches = nested.fetch(row[child.link.parent_column], [])
      child.link.many ? matches : matches.first
    end

    # Fetches a child's rows for all parent rows in one query, grouped by the value that links them.
    def nested_rows(child:, rows:)
      values = rows.map { |row| row[child.link.parent_column] }.compact.uniq
      return {} if values.empty?

      child_rows = fetch_nested(child:, values:)
      link_column = child.join ? LINK : child.link.child_column
      child_rows.zip(shape(node: child, rows: child_rows))
                .group_by { |row, _output| row[link_column] }
                .transform_values { |pairs| pairs.map(&:last) }
    end
  end
end
