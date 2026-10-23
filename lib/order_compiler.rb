# frozen_string_literal: true

class LowData
  # Compiles sort keys into ORDER BY expressions and rows into LIMIT and OFFSET. Each column is qualified with the one
  # table that has it, so `Users[:username] & Posts[:title] ^ Col[:views]` sorts by posts.views.
  class OrderCompiler
    UNPICKED_PAGE_MESSAGE = 'Pick a page after splitting rows into pages, e.g. (Posts[:title] / 20)[0]'

    def initialize(schema:)
      @schema = schema
    end

    def apply(dataset:, keys:, rows:, tables:)
      dataset = dataset.order(*order(keys:, tables:)) if keys.any?
      return dataset unless rows

      check_rows!(rows:)
      dataset.limit(rows.limit, rows.offset.zero? ? nil : rows.offset)
    end

    # Rows without a value sort last in both directions, so `-Col[:views] * 10` is the 10 most viewed on every database.
    # Postgres puts NULLs last ascending and first descending, and SQLite and MySQL the reverse.
    def order(keys:, tables:)
      keys.map do |key|
        column = Sequel[owner(column: key.column, tables:)][key.column]
        key.descending ? column.desc(nulls: :last) : column.asc(nulls: :last)
      end
    end

    def check_rows!(rows:)
      raise ArgumentError, UNPICKED_PAGE_MESSAGE if rows.page_size
    end

    private

    def owner(column:, tables:)
      owners = tables.select { |table| @schema.columns(table:).include?(column) }
      raise JoinError, "No table in #{tables.join(', ')} has a #{column} column to sort by" if owners.empty?
      raise JoinError, "#{owners.join(' and ')} both have a #{column} column, so Col[:#{column}] is ambiguous" if owners.length > 1

      owners.first
    end
  end
end
