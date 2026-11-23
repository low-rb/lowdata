# frozen_string_literal: true

class LowData
  # Reads tables, columns and foreign keys from the database, caching each lookup. Every query shares one per database,
  # so a lookup is made once while the app runs. `Schema.reset` forgets them, as after a migration.
  class Schema
    def self.for(database)
      @instances ||= {}
      @instances[database] ||= new(database:)
    end

    def self.reset
      @instances = {}
    end

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

    def tables
      @tables ||= @database.tables
    end

    # Tables with a foreign key to or from the table, or to its parent.
    def related_tables(table:)
      outgoing = foreign_keys(table:).map { |foreign_key| foreign_key[:table] }
      incoming = tables.select { |other| links(from: other, to: table).any? }

      # Sorted, because databases list their tables in different orders, and error messages name the first.
      ((outgoing + incoming).uniq - [table]).sort
    end

    # Foreign keys on the `from` table that reference the `to` table, as join conditions. `named` keeps only the foreign
    # keys with those columns.
    def references(from:, to:, named: nil)
      links(from:, to:).select { |link| named.nil? || (link[:columns] & named).any? }.map do |link|
        link[:columns].zip(link[:keys]).to_h { |column, key| [Sequel[from][column], Sequel[to][key]] }
      end
    end

    # A renamed column must exist and its new name mustn't, so a rename written backwards, `title: :headline`, raises.
    def check_renames!(table:, renames:)
      columns = columns(table:)

      renames.each do |name, column|
        raise ArgumentError, backwards_rename_message(table:, name:, column:) if columns.include?(name) && !columns.include?(column)
        raise ArgumentError, "#{table} has no #{column} column to rename" unless columns.include?(column)
        raise ArgumentError, "#{table} already has a #{name} column, so #{column} can't be renamed to it" if columns.include?(name)
      end
    end

    def linked?(table, other)
      links(from: table, to: other).any? || links(from: other, to: table).any?
    end

    # Foreign keys on the `from` table that reference the `to` table, as their columns and the keys they reference. A
    # foreign key to the `to` table's parent links to it too, by its primary key, which has the parent's ids.
    def links(from:, to:)
      own = foreign_keys(table: from).select { |foreign_key| foreign_key[:table] == to }.map do |foreign_key|
        { columns: foreign_key[:columns], keys: foreign_key[:key] || primary_key(table: to) }
      end
      own + parent_links(from:, to:)
    end

    # The table a table's primary key is a foreign key to, its parent, like content for posts whose id is content's id.
    def parent(table:)
      foreign_keys(table:).find { |foreign_key| foreign_key[:columns] == primary_key(table:) }&.dig(:table)
    end

    private

    # Foreign keys on the `from` table to the `to` table's parent, as links to the `to` table's primary key.
    def parent_links(from:, to:)
      parent = parent(table: to)
      return [] if parent.nil? || [to, parent].include?(from)

      foreign_keys(table: from).select { |foreign_key| foreign_key[:table] == parent }
                               .map { |foreign_key| { columns: foreign_key[:columns], keys: primary_key(table: to), parent: } }
    end

    def backwards_rename_message(table:, name:, column:)
      "#{table} has no #{column} column. To rename #{name}, write #{column}: :#{name}"
    end

    def schema(table:)
      @schemas[table] ||= @database.schema(table)
    end
  end
end
