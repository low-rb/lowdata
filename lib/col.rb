# frozen_string_literal: true

class LowData
  # Columns to sort by with ^, and optionally which of the sorted rows to keep:
  #   Posts[:title] ^ Col[:views, :title]          # ORDER BY views, title
  #   Posts[:title] ^ -Col[:views]                 # ORDER BY views DESC
  #   Posts[:title] ^ -Col[:views] + Col[:title]   # ORDER BY views DESC, title
  #   Posts[:title] ^ -Col[:views] * 10            # ... LIMIT 10
  #   Posts[:title] ^ -Col[:views][20...40]        # ... LIMIT 20 OFFSET 20
  #   (Posts[:title] ^ -Col[:views] / 20)[2]       # ... LIMIT 20 OFFSET 40
  # Ruby binds -, +, *, / and [] tighter than ^, so the rows travel with the sort keys to the expression.
  class Col
    Key = ::Data.define(:column, :descending)

    attr_reader :keys, :rows

    def self.[](*columns)
      invalid = columns.reject { |column| column.is_a?(Symbol) }
      raise ArgumentError, "Col[] takes column names, e.g. Col[:views], not #{invalid.map(&:inspect).join(', ')}" if invalid.any?
      raise ArgumentError, 'Col[] takes at least one column, e.g. Col[:views]' if columns.empty?

      new(keys: columns.map { |column| Key.new(column:, descending: false) })
    end

    def initialize(keys:, rows: nil)
      @keys = keys
      @rows = rows
      freeze
    end

    def -@
      with(keys: keys.map { |key| key.with(descending: !key.descending) })
    end

    def +(other)
      raise ArgumentError, "Add sort columns with Col[], e.g. -Col[:views] + Col[:title], not #{other.inspect}" unless other.is_a?(Col)

      with(keys: keys + other.keys, rows: Rows.merge(rows, other.rows))
    end

    def *(count)
      with(rows: Rows.merge(rows, Rows.limit(count)))
    end

    def /(size)
      with(rows: Rows.merge(rows, Rows.pages(size)))
    end

    def [](range)
      with(rows: Rows.merge(rows, Rows.range(range)))
    end

    private

    def with(keys: @keys, rows: @rows)
      self.class.new(keys:, rows:)
    end
  end
end
