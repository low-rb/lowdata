# frozen_string_literal: true

class LowData
  # Which sorted rows to keep. Rows count from 0, as in Ruby:
  #   Posts[] * 10                 # LIMIT 10
  #   (Posts[] / 20)[2]            # LIMIT 20 OFFSET 40, the third page of 20
  #   Posts[] ^ Col[:id][20...40]  # LIMIT 20 OFFSET 20
  # Pages have a `page_size` until a page is picked, and a `limit` and `offset` after.
  Rows = ::Data.define(:offset, :limit, :page_size) do
    def self.limit(count)
      new(offset: 0, limit: positive!(count:, operator: '*'), page_size: nil)
    end

    def self.pages(size)
      new(offset: 0, limit: nil, page_size: positive!(count: size, operator: '/'))
    end

    def self.range(range)
      check_range!(range:)
      first = range.begin || 0
      return new(offset: first, limit: nil, page_size: nil) if range.end.nil?

      new(offset: first, limit: [range.end - first + (range.exclude_end? ? 0 : 1), 0].max, page_size: nil)
    end

    # One limit, range or page size per expression.
    def self.merge(rows, other)
      raise ArgumentError, 'An expression takes one limit, range or page size, not two' if rows && other

      rows || other
    end

    def self.check_range!(range:)
      unless range.is_a?(Range) && [range.begin, range.end].all? { |bound| bound.nil? || bound.is_a?(Integer) }
        raise ArgumentError, "Pick rows with a range of integers, e.g. Col[:views][20...40], not #{range.inspect}"
      end
      raise ArgumentError, "Rows count from 0, so #{range.inspect} can't start below 0" if range.begin&.negative?
    end

    def self.positive!(count:, operator:)
      return count if count.is_a?(Integer) && count.positive?

      raise ArgumentError, "#{operator} takes a positive integer, e.g. Posts[:title] #{operator} 10, not #{count.inspect}"
    end

    def page(number)
      raise ArgumentError, 'Split rows into pages before picking one, e.g. (Posts[:title] / 20)[0]' unless page_size
      unless number.is_a?(Integer) && !number.negative?
        raise ArgumentError, "Pages count from 0, so pick one with an integer from 0, not #{number.inspect}"
      end

      with(offset: number * page_size, limit: page_size, page_size: nil)
    end
  end
end
