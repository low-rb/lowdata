# frozen_string_literal: true

class LowData
  # A table named by a constant, such as `Users`, waiting for its columns: `Users[:username]`.
  # An inverted reference is `Table`, standing in for the repository's table and any table related to it.
  # A reference can carry filters from round brackets, `Posts(published: true)`, and be negated with `~Posts`.
  class TableReference
    FILTER_KEYWORD_MESSAGE = 'Filters go in round brackets, e.g. Posts(published: true)[:title], not %<keywords>s'

    attr_reader :table, :filter, :negated

    def initialize(table:, inverted: false, filter: DataExpression::Filter.new, negated: false)
      @table = table
      @inverted = inverted
      @filter = filter
      @negated = negated
    end

    # Each argument's type decides its meaning:
    #   Posts[:title]                              # A symbol is a column. No columns selects every column.
    #   Users[:username, Posts[:title]]            # A data expression is a nested table.
    #   Reviews[:rating, author: Users[:username]] # A keyword with a data expression names a nested table.
    #   Posts[:id, headline: :title]               # A keyword with a symbol renames a column.
    def [](*arguments, **keywords)
      raise ArgumentError, "~#{LowData.constant_name(table)} filters by related rows, so it can't select columns" if negated
      return inverted(arguments:, keywords:) if @inverted

      expressions, columns = arguments.partition { |argument| argument.is_a?(DataExpression) }
      check_columns!(columns:)
      named, renames = named(keywords:, columns:)
      nested = nested(pairs: expressions.map { |expression| [nil, expression] } + named)

      DataExpression.new(node: DataExpression::Source.new(table:, columns:, renames:, nested:, filter:))
    end

    # Each argument's type decides its meaning:
    #   Posts(published: true)                     # A keyword with a value filters by that value.
    #   Posts { views > 100 }                      # A block is a Sequel virtual row condition.
    #   Users(Posts), Users(~Posts)                # A table keeps rows with, or without, related rows.
    #   Users(Posts => 3..)                        # A table as a key keeps rows with that many related rows.
    #   Reviews(author: Users(username: 'alice'))  # A keyword with a table names the foreign key to follow.
    def where(*arguments, **keywords, &block)
      related = arguments.map { |argument| related(key: nil, reference: argument) }
      values = {}

      keywords.each do |key, value|
        if key.is_a?(TableReference) then related << related(key: nil, reference: key, count: value)
        elsif value.is_a?(TableReference) then related << related(key:, reference: value)
        else values[key] = value
        end
      end

      conditions = block ? [Sequel.virtual_row(&block)] : []
      with(filter: filter.merge(DataExpression::Filter.new(values:, conditions:, related:)))
    end

    # `~Posts` keeps rows without related posts.
    def ~
      with(negated: !negated)
    end

    def source
      DataExpression::Source.new(table:, columns: [], filter:)
    end

    private

    def with(filter: @filter, negated: @negated)
      self.class.new(table:, inverted: @inverted, filter:, negated:)
    end

    def related(key:, reference:, count: nil)
      unless reference.is_a?(TableReference)
        raise ArgumentError, "Round brackets take filters and tables, e.g. Posts(published: true) or Users(Posts), not #{reference.inspect}"
      end
      raise ArgumentError, "Write ~#{LowData.constant_name(reference.table)} or a count, not both" if reference.negated && count

      DataExpression::Related.new(key:, source: reference.source, count: count || (reference.negated ? 0 : 1..))
    end

    # Returns the named nested tables and the renamed columns.
    def named(keywords:, columns:)
      named, others = keywords.partition { |_key, value| value.is_a?(DataExpression) }
      renames, filters = others.partition { |_key, value| value.is_a?(Symbol) }
      raise ArgumentError, format(FILTER_KEYWORD_MESSAGE, keywords: filters.to_h) if filters.any?

      check_renames!(names: columns + named.map(&:first), renames: renames.to_h)
      [named, renames.to_h]
    end

    def check_renames!(names:, renames:)
      duplicate = (renames.keys & names).first
      raise ArgumentError, "#{LowData.constant_name(table)}[] returns #{duplicate} twice. Name each value once" if duplicate
    end

    def nested(pairs:)
      pairs.map { |key, expression| DataExpression::Nested.new(key:, node: expression.node) }
    end

    def inverted(arguments:, keywords:)
      check_columns!(columns: arguments)
      raise ArgumentError, 'Table[] takes column names only, and renames such as headline: :title' unless keywords.values.all?(Symbol)

      check_renames!(names: arguments, renames: keywords)
      DataExpression.new(node: DataExpression::Inversion.new(table:, columns: arguments, renames: keywords, filter:))
    end

    def check_columns!(columns:)
      invalid = columns.reject { |column| column.is_a?(Symbol) }
      raise ArgumentError, "Columns are symbols, e.g. Posts[:title], not #{invalid.map(&:inspect).join(', ')}" if invalid.any?
    end
  end
end
