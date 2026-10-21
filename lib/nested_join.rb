# frozen_string_literal: true

class LowData
  # A join in a nesting tree, loaded with one query by QueryCompiler. It nests as flat rows through `table`, the one of
  # its `tables` linked to the parent, and tables nest under each of its rows:
  #   Users[:username] + (Posts[:title] & Comments[:body]) # => [{ username: 'alice', posts: [{ title: 'Hello', body: 'Nice' }] }]
  #   (Users[:username] & Posts[:title]) + Comments[:body] # => [{ username: 'alice', title: 'Hello', comments: [{ body: 'Nice' }] }]
  NestedJoin = ::Data.define(:node, :tables, :table)

  class NestedJoin
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
      table = linked_table(others: [parent], schema:)
      key, link = tree.link_to(parent:, child: table, key:)
      raise JoinError, one_side_message(parent:, table:) unless link.many

      [with(table:), key, link]
    end

    # The one of the join's tables linked to any of `others`.
    def linked_table(others:, schema:)
      linked = tables.select { |table| others.any? { |other| schema.linked?(table, other) } }
      names = others.join(', ')
      raise JoinError, "No foreign key links #{tables.join(', ')} to #{names}" if linked.empty?
      raise JoinError, "#{linked.join(' and ')} both link to #{names}, so the join has no single way to nest" if linked.length > 1

      linked.first
    end

    private

    def one_side_message(parent:, table:)
      "#{parent} points to #{table}, so a join with #{table} can't nest in #{parent}, because its rows can repeat " \
        "#{table}. Nest #{table} in brackets instead"
    end
  end
end
