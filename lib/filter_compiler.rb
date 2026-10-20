# frozen_string_literal: true

class LowData
  # Compiles a table's filter into WHERE conditions, each qualified with the table:
  #   Posts(published: true)        # WHERE posts.published IS TRUE
  #   Posts { views > 100 }         # WHERE posts.views > 100
  #   Users(Posts)                  # WHERE EXISTS (SELECT 1 FROM posts WHERE posts.user_id = users.id)
  #   Users(Posts => 3..)           # WHERE (SELECT count(*) FROM posts WHERE posts.user_id = users.id) >= 3
  class FilterCompiler
    def initialize(database:, schema:)
      @database = database
      @links = NestingTree.new(schema:)
    end

    def apply(dataset:, source:)
      conditions(source:).reduce(dataset) { |filtered, condition| filtered.where(condition) }
    end

    private

    def conditions(source:)
      table = source.table
      filter = source.filter
      values = filter.values.map { |column, value| { Sequel[table][column] => value } }
      conditions = filter.conditions.map { |condition| Sequel::Qualifier.new(table).transform(condition) }

      values + conditions + filter.related.map { |related| related_condition(table:, related:) }
    end

    # Correlates the related table's rows with the outer table's by the foreign key that links them, as nesting does.
    def related_condition(table:, related:)
      inner = related.source.table
      raise JoinError, "Can't filter #{table} by its own rows" if inner == table

      _key, link = @links.link_to(parent: table, child: inner, key: related.key)
      rows = @database[inner].where(Sequel[inner][link.child_column] => Sequel[table][link.parent_column])
      count(rows: apply(dataset: rows, source: related.source), count: related.count)
    end

    def count(rows:, count:)
      return rows.select(1).exists if count == (1..)
      return ~rows.select(1).exists if [0, 0..0].include?(count)

      { rows.select(Sequel.function(:count).*) => count }
    end
  end
end
