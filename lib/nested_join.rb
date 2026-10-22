# frozen_string_literal: true

class LowData
  # A join in a nesting tree, loaded with one query by QueryCompiler. It nests as flat rows through `table`, the one of
  # its `tables` linked to the parent, and tables nest under each of its rows:
  #   Users[:username] + (Posts[:title] & Comments[:body]) # => [{ username: 'alice', posts: [{ title: 'Hello', body: 'Nice' }] }]
  #   (Users[:username] & Posts[:title]) + Comments[:body] # => [{ username: 'alice', title: 'Hello', comments: [{ body: 'Nice' }] }]
  #
  # When more than one of its tables links, a foreign key named in round brackets picks the one:
  #   Users[:username] + (Posts(:user_id)[:title] & Likes[:id]) # Posts and likes both link to users, by posts.user_id.
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

    # The one of the join's tables linked to any of `others`, picked by a foreign key named in round brackets when more
    # than one is. `foreign_keys` are the named foreign keys of `others`, by table. `nested` is true when the join nests
    # in `others`, and false when `others` nest in the join.
    def linked_table(others:, schema:, foreign_keys:, nested: false)
      linked = tables.select { |table| others.any? { |other| schema.linked?(table, other) } }
      raise JoinError, "No foreign key links #{tables.join(', ')} to #{others.join(', ')}" if linked.empty?

      linked = named(linked:, others:, schema:, foreign_keys: self.foreign_keys.merge(foreign_keys)) if linked.length > 1
      raise JoinError, ambiguous_message(linked:, others:, nested:, schema:) if linked.length > 1

      linked.first
    end

    private

    # The linked tables whose foreign key to `others`, on either side, is named in round brackets, or all of them if none is.
    def named(linked:, others:, schema:, foreign_keys:)
      named = linked.select do |table|
        others.any? do |other|
          columns = (schema.links(from: table, to: other) + schema.links(from: other, to: table)).flat_map { |link| link[:columns] }
          (columns & (foreign_keys.fetch(table, []) + foreign_keys.fetch(other, []))).any?
        end
      end
      named.empty? ? linked : named
    end

    # Suggests naming each foreign key that could link them, on the table that has it.
    def ambiguous_message(linked:, others:, nested:, schema:)
      names = others.join(', ')
      problem = nested ? "the join can't nest in #{names}" : "#{names} can't nest in the join"
      choices = linked.product(others).flat_map do |table, other|
        [[table, other], [other, table]].flat_map do |from, to|
          schema.links(from:, to:).map { |link| "#{LowData.constant_name(from)}(:#{link[:columns].first})" }
        end
      end

      "#{linked.join(' and ')} both link to #{names}, so #{problem} by a single foreign key. " \
        "Name the foreign key to nest by in round brackets: #{choices.join(' or ')}"
    end

    def one_side_message(parent:, table:)
      "#{parent} points to #{table}, so a join with #{table} can't nest in #{parent}, because its rows can repeat " \
        "#{table}. Nest #{table} in brackets instead"
    end
  end
end
