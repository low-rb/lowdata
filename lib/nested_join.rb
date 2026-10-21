# frozen_string_literal: true

class LowData
  # A join nested as flat rows, loaded with one query by QueryCompiler:
  #   Users[:username] + (Posts[:title] & Comments[:body]) # => [{ username: 'alice', posts: [{ title: 'Hello', body: 'Nice' }] }]
  # It nests through `table`, the one of its `tables` linked to the parent.
  NestedJoin = ::Data.define(:node, :tables, :table)

  class NestedJoin
    PARENT_MESSAGE = 'A join returns flat rows, so tables can\'t nest under it. Nest the join instead, ' \
                     'e.g. Users[:username] + (Posts[:title] & Comments[:body])'

    def self.build(node:)
      new(node:, tables: tables_in(node:), table: nil)
    end

    # A join holds only tables joined with &, <, > or <=>, as QueryCompiler requires.
    def self.tables_in(node:)
      raise JoinError, QueryCompiler::INVERSION_JOIN_MESSAGE if node.is_a?(DataExpression::Inversion)
      raise JoinError, QueryCompiler::ORDERED_JOIN_MESSAGE if node.is_a?(DataExpression::Ordered)
      return [node.table] if node.is_a?(DataExpression::Source)
      raise JoinError, QueryCompiler::NESTING_JOIN_MESSAGE if node.nest?

      tables_in(node: node.left) + tables_in(node: node.right)
    end

    # Returns the join with its table, and the key and Link that nest it under `parent`. Only the "many" side can nest a
    # join, because joined rows can repeat the table's rows.
    def link(parent:, key:, tree:, schema:)
      linked = tables.select { |table| schema.linked?(parent, table) }
      raise JoinError, "No foreign key links #{tables.join(', ')} to #{parent}" if linked.empty?
      raise JoinError, "#{linked.join(' and ')} both link to #{parent}, so the join has no single way to nest" if linked.length > 1

      key, link = tree.link_to(parent:, child: linked.first, key:)
      raise JoinError, one_side_message(parent:, table: linked.first) unless link.many

      [with(table: linked.first), key, link]
    end

    private

    def one_side_message(parent:, table:)
      "#{parent} points to #{table}, so a join with #{table} can't nest in #{parent}, because its rows can repeat " \
        "#{table}. Nest #{table} in brackets instead"
    end
  end
end
