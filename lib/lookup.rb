# frozen_string_literal: true

class LowData
  # Resolves a chain of + many-to-one joins, such as `Users[:username] + Posts[:title] + Comments[:body]`, in any order.
  # The subject is the one table no other table in the chain points to, here comments. Every other table is left joined
  # by following foreign keys up from it, so each subject row appears exactly once.
  class Lookup
    def initialize(schema:)
      @schema = schema
    end

    # Returns a join tree that starts from the subject and left joins each parent table.
    def resolve(sources:)
      tables = sources.map(&:table)
      check_duplicates!(tables:)

      parents = tables.to_h { |table| [table, tables.select { |other| other != table && points_to?(from: table, to: other) }] }
      order = join_order(subject: subject(tables:, parents:), parents:)
      check_reached!(tables:, order:)

      tree(sources:, order:)
    end

    private

    def points_to?(from:, to:)
      @schema.references(from:, to:).any?
    end

    def subject(tables:, parents:)
      children = tables.to_h { |table| [table, tables.select { |other| parents[other].include?(table) }] }
      check_links!(tables:, parents:, children:)

      subjects = tables.select { |table| children[table].empty? }
      raise JoinError, "#{subjects.join(' and ')} aren't linked by foreign keys" if subjects.length > 1
      raise JoinError, "The foreign keys between #{tables.join(', ')} form a cycle" if subjects.empty?

      subjects.first
    end

    def check_links!(tables:, parents:, children:)
      unlinked = tables.find { |table| parents[table].empty? && children[table].empty? }
      raise JoinError, "No foreign key links #{unlinked} to #{(tables - [unlinked]).join(', ')}" if unlinked

      shared = tables.find { |table| children[table].length > 1 }
      raise JoinError, many_message(table: shared, children: children[shared]) if shared
    end

    def check_duplicates!(tables:)
      duplicate = tables.find { |table| tables.count(table) > 1 }
      raise JoinError, "Can't join #{duplicate} to itself" if duplicate
    end

    def check_reached!(tables:, order:)
      unreached = tables - order
      raise JoinError, "No foreign key path links #{unreached.join(' and ')} to #{order.join(', ')}" if unreached.any?
    end

    def tree(sources:, order:)
      by_table = sources.to_h { |source| [source.table, source] }

      order.drop(1).reduce(by_table[order.first]) do |left, table|
        DataExpression::Join.new(type: :left, left:, right: by_table[table])
      end
    end

    # Breadth first from the subject, so each table is joined after the table that points to it.
    def join_order(subject:, parents:)
      order = [subject]
      order.each { |table| parents[table].each { |parent| order << parent unless order.include?(parent) } }
      order
    end

    def many_message(table:, children:)
      "#{children.join(' and ')} both point to #{table}, so + has no single table to keep. " \
        'Use < for a left join, or Table[] in a repository'
    end
  end
end
