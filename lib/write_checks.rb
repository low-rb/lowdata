# frozen_string_literal: true

class LowData
  # Checks a write before it runs, so a mistake raises rather than writing the wrong rows. See Writer.
  module WriteChecks
    ROWS_MESSAGE = '%<operator>s takes a hash or an array of hashes, e.g. Posts %<operator>s { title: \'Hello\' }, not %<rows>s'
    INSERT_FILTER_MESSAGE = 'An insert adds new rows, so it takes no round brackets. To insert a row or update the one ' \
                            'matching the round brackets, upsert with <=, e.g. Posts(slug: \'hello\') <= { title: \'Hello\' }'
    UPSERT_FILTER_MESSAGE = 'An upsert matches one row by plain values, e.g. Posts(slug: \'hello\') <= row, so it takes no ' \
                            'ranges, lists, blocks or tables in round brackets'
    FOREIGN_KEY_MESSAGE = "A symbol in round brackets names a foreign key for a nested join, so it can't choose rows to %<action>s"
    # `Posts[:id] <= Users[:id]` reads like a comparison or a join, so it says what `<=` does instead.
    EXPRESSION_MESSAGES = {
      '<<' => "<< inserts rows, e.g. Posts << { title: 'Hello' }, not a data expression",
      '<=' => "<= upserts rows, e.g. Posts(slug: 'hello') <= { title: 'Hello' }, so it can't compare or join data expressions. " \
              'Join them with &, <, > or <=>'
    }.freeze

    private

    def check_rows!(rows:, operator:)
      return if rows.is_a?(Hash) || (rows.is_a?(Array) && rows.all?(Hash))
      raise ArgumentError, EXPRESSION_MESSAGES.fetch(operator) if rows.is_a?(DataExpression)

      raise ArgumentError, format(ROWS_MESSAGE, operator:, rows: rows.inspect)
    end

    def check_insert_filter!(filter:)
      raise ArgumentError, INSERT_FILTER_MESSAGE if chooses_rows?(filter:)
    end

    # Whether the round brackets choose rows. Foreign keys only name how a nested join links.
    def chooses_rows?(filter:)
      filter.values.any? || filter.conditions.any? || filter.related.any?
    end

    def check_upsert_filter!(filter:)
      plain = filter.values.values.none? { |value| value.is_a?(Range) || value.is_a?(Enumerable) || value.is_a?(Sequel::SQL::Expression) }
      return if plain && filter.conditions.empty? && filter.related.empty? && filter.foreign_keys.empty?

      raise ArgumentError, UPSERT_FILTER_MESSAGE
    end

    # An update or delete without round brackets would change every row, so it raises. `dataset` can still do that.
    def check_chosen!(source:, action:, example:)
      filter = source.filter
      raise ArgumentError, format(FOREIGN_KEY_MESSAGE, action:) if filter.foreign_keys.any?
      return if chooses_rows?(filter:)

      raise ArgumentError, "Choose the #{source.table} to #{action} with round brackets, e.g. #{example}"
    end

    # MySQL's ON DUPLICATE KEY UPDATE matches any unique key, so the upsert must match on one, and the row mustn't set
    # every column of another, which could match a different row. An auto-increment id left out of the row can't match.
    def check_mysql_keys!(table:, keys:, row:, target:)
      matched, others = keys.partition { |key| key.sort == target.sort }
      raise Error, "MySQL upserts match on a unique key, and #{target.join(', ')} isn't one of #{table}'s" if matched.empty?

      clashing = others.find { |key| key.none? { |column| row[column].nil? } }
      return unless clashing

      raise Error, "MySQL matches an upsert on any unique key, and the row also sets #{clashing.join(', ')}, which could match " \
                   "another #{table} row. Leave #{clashing.join(', ')} out of the row, or match on it"
    end

    # Checked before the write, so a typo doesn't write a row and then fail to return it.
    def check_returned!(source:, columns:)
      missing = (source.columns + source.renames.values) - columns
      raise ArgumentError, "#{source.table} has no #{missing.join(', ')} column to return" if missing.any?
    end

    def assignment(values:)
      return "[:#{values.keys.first}] = #{values.values.first.inspect}" if values.one?

      "[] = #{values.inspect}"
    end
  end
end
