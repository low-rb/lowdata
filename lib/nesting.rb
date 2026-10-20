# frozen_string_literal: true

class LowData
  # Loads nested data, one query per table. Tables nest explicitly in brackets, or by inference with +:
  #   Posts[:title, Users[:username]]  # => [{ title: 'Hello', user: { username: 'alice' } }]
  #   Users[:username] + Posts[:title] # => [{ username: 'alice', posts: [{ title: 'Hello' }] }]
  # In a + chain the first table is the subject, and each other operand nests under the table its foreign key links it to.
  class Nesting
    # A table in the nesting tree. `link` connects it to its parent node: `parent_column` on the parent's rows matches
    # `child_column` on this table's rows, and `many` nests the matches as an array rather than one object.
    Node = ::Data.define(:source, :key, :link, :children)
    Link = ::Data.define(:parent_column, :child_column, :many)

    def initialize(database:)
      raise ConfigError, ConfigError::MISSING_DATABASE if database.nil?

      @database = database
      @schema = Schema.new(database:)
    end

    def load(node:)
      root = NestingTree.new(schema: @schema).build(node:)
      shape(node: root, rows: fetch(node: root))
    end

    private

    def fetch(node:, filter: nil)
      dataset = @database[node.source.table].select(*select_columns(node:))
      dataset = dataset.where(node.source.filters) if node.source.filters.any?
      filter ? dataset.where(filter).all : dataset.all
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
