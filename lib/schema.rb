# frozen_string_literal: true

class LowData
  # Reads tables, columns and foreign keys from the database, caching each lookup.
  class Schema
    def initialize(database:)
      @database = database
      @schemas = {}
      @foreign_keys = {}
    end

    def columns(table:)
      schema(table:).map(&:first)
    end

    def primary_key(table:)
      schema(table:).select { |_column, info| info[:primary_key] }.map(&:first)
    end

    def foreign_keys(table:)
      @foreign_keys[table] ||= @database.foreign_key_list(table)
    end

    # Tables with a foreign key to or from the table.
    def related_tables(table:)
      outgoing = foreign_keys(table:).map { |foreign_key| foreign_key[:table] }
      incoming = @database.tables.select do |other|
        foreign_keys(table: other).any? { |foreign_key| foreign_key[:table] == table }
      end

      (outgoing + incoming).uniq - [table]
    end

    # Foreign keys on the `from` table that reference the `to` table, as join conditions.
    def references(from:, to:)
      links(from:, to:).map do |link|
        link[:columns].zip(link[:keys]).to_h { |column, key| [Sequel[from][column], Sequel[to][key]] }
      end
    end

    def linked?(table, other)
      links(from: table, to: other).any? || links(from: other, to: table).any?
    end

    # Foreign keys on the `from` table that reference the `to` table, as their columns and the keys they reference.
    def links(from:, to:)
      foreign_keys(table: from).select { |foreign_key| foreign_key[:table] == to }.map do |foreign_key|
        { columns: foreign_key[:columns], keys: foreign_key[:key] || primary_key(table: to) }
      end
    end

    private

    def schema(table:)
      @schemas[table] ||= @database.schema(table)
    end
  end
end
