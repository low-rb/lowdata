# frozen_string_literal: true

class LowData
  # Loads nested data, one query per table. Tables nest explicitly in brackets, or by inference with +:
  #   Posts[:title, Users[:username]]  # => [{ title: 'Hello', user: { username: 'alice' } }]
  #   Users[:username] + Posts[:title] # => [{ username: 'alice', posts: [{ title: 'Hello' }] }]
  # In a + chain the first table is the subject, and each other operand nests under the table its foreign key links it to.
  class Nesting
    # A table in the nesting tree. `link` connects it to its parent node: `parent_column` on the parent's rows matches
    # `child_column` on this table's rows, and `many` nests the matches as an array rather than one object.
    # `keys` and `rows` sort and limit the table's rows, per parent when it's nested.
    Node = ::Data.define(:source, :key, :link, :children, :keys, :rows) do
      def initialize(source:, key:, link:, children:, keys: [], rows: nil)
        super
      end
    end
    Link = ::Data.define(:parent_column, :child_column, :many)

    ROW_NUMBER = :lowdata_row_number

    def initialize(database:)
      raise ConfigError, ConfigError::MISSING_DATABASE if database.nil?

      @database = database
      @schema = Schema.new(database:)
      @filters = FilterCompiler.new(database:, schema: @schema)
      @orders = OrderCompiler.new(schema: @schema)
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

    # Keeps each parent's rows, e.g. each user's 3 most viewed posts, by numbering the rows within each parent.
    def per_parent(node:, dataset:)
      numbered = dataset.select_append(row_number(node:).as(ROW_NUMBER))
      @database.from(numbered).where(ROW_NUMBER => row_numbers(rows: node.rows)).order(ROW_NUMBER)
               .all.map { |row| row.except(ROW_NUMBER) }
    end

    def row_number(node:)
      table = node.source.table
      order = @orders.order(keys: node.keys, tables: [table])
      Sequel.function(:row_number).over(partition: Sequel[table][node.link.child_column], order: order.empty? ? nil : order)
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
        output = node.source.columns.empty? ? row.dup : row.slice(*node.source.columns)
        node.children.each { |child| output[child.key] = matches(child:, row:, nested: nested[child]) }
        output
      end
    end

    def matches(child:, row:, nested:)
      matches = nested.fetch(row[child.link.parent_column], [])
      child.link.many ? matches : matches.first
    end

    # Fetches a child's rows for all parent rows in one query, grouped by the value that links them.
    def nested_rows(child:, rows:)
      values = rows.map { |row| row[child.link.parent_column] }.compact.uniq
      return {} if values.empty?

      child_rows = fetch(node: child, filter: { child.link.child_column => values })
      child_rows.zip(shape(node: child, rows: child_rows))
                .group_by { |row, _output| row[child.link.child_column] }
                .transform_values { |pairs| pairs.map(&:last) }
    end
  end
end
