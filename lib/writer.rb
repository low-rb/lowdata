# frozen_string_literal: true

require_relative 'write_checks'

class LowData
  # Runs writes as soon as they're written, and returns what they wrote. See ADR 0007:
  #   Posts << { title: 'Hello' }                 # INSERT, returning the primary key
  #   Posts[:id, :title] << { title: 'Hello' }    # INSERT, returning the columns in square brackets
  #   Posts(slug: 'hello') <= { title: 'Hello' }  # INSERT ... ON CONFLICT (slug) DO UPDATE, returning the primary key
  #   Posts(id: 1)[:title] = 'New'                # UPDATE ... WHERE (posts.id = 1)
  #   Posts(id: 1).delete                         # DELETE ... WHERE (posts.id = 1), returning the number of rows deleted
  class Writer
    include WriteChecks

    def initialize(database:)
      raise ConfigError, ConfigError::MISSING_DATABASE if database.nil?

      @database = database
      @schema = Schema.new(database:)
      @filters = FilterCompiler.new(database:, schema: @schema)
    end

    def insert(source:, rows:)
      check_rows!(rows:, operator: '<<')
      check_insert_filter!(filter: source.filter)
      return insert_all(source:, rows:) if source.no_columns? && rows.is_a?(Array) && rows.map(&:keys).uniq.one?

      each_row(rows:) { |row| insert_row(source:, row:) }
    end

    # The round brackets name the columns to match on, and their values are written too.
    def upsert(source:, rows:)
      check_rows!(rows:, operator: '<=')
      check_upsert_filter!(filter: source.filter)

      each_row(rows:) { |row| upsert_row(source:, row: source.filter.values.merge(row)) }
    end

    def update(source:, values:)
      check_chosen!(source:, action: 'update', example: "#{constant(source:)}(id: 1)#{assignment(values:)}")

      chosen(source:).update(values)
    end

    def delete(source:)
      check_chosen!(source:, action: 'delete', example: "#{constant(source:)}(id: 1).delete")

      chosen(source:).delete
    end

    private

    # A hash writes one row and returns a hash, and an array writes each row in a transaction and returns an array.
    def each_row(rows:, &)
      return yield(rows) if rows.is_a?(Hash)

      @database.transaction { rows.map(&) }
    end

    # Empty brackets return nothing, so rows with the same columns go in one INSERT, as nothing needs matching back to
    # them. Otherwise rows insert one by one, because RETURNING doesn't promise the inserted order, and a multi-row
    # INSERT takes its columns from the first row, so a column missing from it would be dropped.
    def insert_all(source:, rows:)
      @database[source.table].multi_insert(rows)
      rows.map { {} }
    end

    def insert_row(source:, row:)
      dataset = @database[source.table]
      return dataset.returning(*returned(source:)).insert(row).first if returning?(dataset:, source:)

      id = dataset.insert(row)
      read_back(source:, keys: inserted_keys(table: source.table, row:, id:))
    end

    def upsert_row(source:, row:)
      target = conflict_target(source:, row:)
      return mysql_upsert(source:, row:, target:) if @database.database_type == :mysql

      dataset = @database[source.table]
      raise Error, "LowData can't upsert on #{@database.database_type}" unless dataset.respond_to?(:insert_conflict)

      dataset = dataset.insert_conflict(target:, update: updates(row:, target:))
      return dataset.returning(*returned(source:)).insert(row).first if returning?(dataset:, source:)

      dataset.insert(row)
      read_back(source:, keys: row.slice(*target))
    end

    # MySQL's ON DUPLICATE KEY UPDATE matches any unique key, so the named columns must be the table's only one.
    def mysql_upsert(source:, row:, target:)
      unless unique_keys(table: source.table).map(&:sort) == [target.sort]
        raise Error, "MySQL matches an upsert on any unique key, so #{target.join(', ')} must be #{source.table}'s only unique key"
      end

      @database[source.table].on_duplicate_key_update(*updates(row:, target:).keys).insert(row)
      read_back(source:, keys: row.slice(*target))
    end

    def unique_keys(table:)
      indexes = @database.indexes(table).values.select { |index| index[:unique] }.map { |index| index[:columns] }
      ([@schema.primary_key(table:)] + indexes).reject(&:empty?)
    end

    # Without round brackets, an upsert matches on the primary key.
    def conflict_target(source:, row:)
      return source.filter.values.keys if source.filter.values.any?

      primary_key = @schema.primary_key(table: source.table)
      missing = primary_key - row.keys
      return primary_key if primary_key.any? && missing.empty?

      raise ArgumentError, "#{constant(source:)} <= row matches on the primary key, so the row needs #{missing.join(', ')}. " \
                           "Or name the columns to match in round brackets, e.g. #{constant(source:)}(slug: 'hello') <= row"
    end

    # A row of only the matched columns still updates one of them, so the database returns the row rather than nothing.
    def updates(row:, target:)
      columns = row.keys - target
      (columns.empty? ? [target.first] : columns).to_h { |column| [column, Sequel[:excluded][column]] }
    end

    # Square brackets choose the columns returned, and a bare table returns its primary key, or every column without one.
    def returned(source:)
      return @schema.primary_key(table: source.table) if source.every_column?

      check_returned!(source:, columns: @schema.columns(table: source.table))
      source.columns + source.renames.map { |name, column| Sequel.as(column, name) }
    end

    # Empty brackets return no columns, and databases without RETURNING read the row back by its keys.
    def read_back(source:, keys:)
      return {} if source.no_columns?

      @database[source.table].where(keys).select(*returned(source:)).first
    end

    def returning?(dataset:, source:)
      dataset.supports_returning?(:insert) && !source.no_columns?
    end

    def inserted_keys(table:, row:, id:)
      primary_key = @schema.primary_key(table:)
      return row if primary_key.empty?
      return { primary_key.first => id } if primary_key.one? && !row.key?(primary_key.first)

      row.slice(*primary_key)
    end

    def chosen(source:)
      @filters.apply(dataset: @database[source.table], source:)
    end

    def constant(source:)
      LowData.constant_name(source.table)
    end
  end
end
