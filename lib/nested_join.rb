# frozen_string_literal: true

class LowData
  # A join in a nesting tree, loaded with one query by QueryCompiler. It nests as flat rows, and tables nest under each
  # of its rows, through its table written next to the +: its first table after a +, and its last table before one.
  #   Users[:username] + (Posts[:title] & Comments[:body]) # => [{ username: 'alice', posts: [{ title: 'Hello', body: 'Nice' }] }]
  #   (Users[:username] & Posts[:title]) + Comments[:body] # => [{ username: 'alice', title: 'Hello', comments: [{ body: 'Nice' }] }]
  #
  # A foreign key named in round brackets links through another of its tables:
  #   Users[:username] + (Posts[:title] & Likes(:user_id)[:id]) # Links through likes.user_id.
  NestedJoin = ::Data.define(:node, :tables, :table, :foreign_keys)

  class NestedJoin
    def self.build(node:)
      sources = sources_in(node:)
      foreign_keys = sources.to_h { |source| [source.table, source.filter.foreign_keys] }
      new(node:, tables: sources.map(&:table), table: nil, foreign_keys:)
    end

    # A join holds only tables joined with &, <, > or <=>, as QueryCompiler requires.
    def self.sources_in(node:)
      raise JoinError, QueryCompiler::INVERSION_JOIN_MESSAGE if node.is_a?(DataExpression::Inversion)
      raise JoinError, QueryCompiler::ORDERED_JOIN_MESSAGE if node.is_a?(DataExpression::Ordered)
      return [node] if node.is_a?(DataExpression::Source)
      raise JoinError, QueryCompiler::NESTING_JOIN_MESSAGE if node.nest?

      sources_in(node: node.left) + sources_in(node: node.right)
    end

    # Returns the join with its table, and the key and Link that nest it under `parent`. Only the "many" side can nest a
    # join, because joined rows can repeat the table's rows.
    def link(parent:, key:, tree:, schema:, foreign_keys:)
      table = linked_table(others: [parent], schema:, foreign_keys:, nested: true)
      key, link = tree.link_to(parent:, child: table, key:)
      raise JoinError, one_side_message(parent:, table:) unless link.many

      [with(table:), key, link]
    end

    # The table the join links to `others` through: the one written next to the +, unless a foreign key named in round
    # brackets links another. `foreign_keys` are the named foreign keys of `others`, by table. `nested` is true when the
    # join nests in `others`, so the + is before its first table, and false when `others` nest in it, after its last.
    def linked_table(others:, schema:, foreign_keys:, nested: false)
      named = named(others:, schema:, foreign_keys: self.foreign_keys.merge(foreign_keys))
      table = named.first || (nested ? tables.first : tables.last)
      return table if others.any? { |other| schema.linked?(table, other) }

      raise JoinError, unlinked_message(table:, others:, schema:)
    end

    private

    # The join's tables whose foreign key to `others`, on either side, is named in round brackets.
    def named(others:, schema:, foreign_keys:)
      tables.select do |table|
        others.any? do |other|
          columns = (schema.links(from: table, to: other) + schema.links(from: other, to: table)).flat_map { |link| link[:columns] }
          (columns & (foreign_keys.fetch(table, []) + foreign_keys.fetch(other, []))).any?
        end
      end
    end

    # Suggests naming the foreign key of another of the join's tables that links, on the table that has it.
    def unlinked_message(table:, others:, schema:)
      names = others.join(', ')
      choices = (tables - [table]).product(others).flat_map do |linked, other|
        [[linked, other], [other, linked]].flat_map do |from, to|
          schema.links(from:, to:).map { |link| "#{LowData.constant_name(from)}(:#{link[:columns].first})" }
        end
      end
      message = "No foreign key links #{table} to #{names}, and a join links through its table written next to the +"
      return message if choices.empty?

      "#{message}. Write the table that links next to the +, or name its foreign key: #{choices.sort.join(' or ')}"
    end

    def one_side_message(parent:, table:)
      "#{parent} points to #{table}, so a join with #{table} can't nest in #{parent}, because its rows can repeat " \
        "#{table}. Nest #{table} in brackets instead"
    end
  end
end
