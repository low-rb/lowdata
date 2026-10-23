# frozen_string_literal: true

class LowData
  # A table named by a constant, such as `Users`. Square brackets choose its columns, `Users[:username]`, and on its own
  # it's every column. See ADR 0006.
  # An inverted reference is `Table`, standing in for the repository's table and any table related to it.
  # A reference can carry filters from round brackets, `Posts(published: true)`, and be negated with `~Posts`.
  class TableReference
    FILTER_KEYWORD_MESSAGE = 'Filters go in round brackets, e.g. Posts(published: true)[:title], not %<keywords>s'
    BARE_TABLE_MESSAGE = 'Table joins the tables that own the columns it selects, so name them, e.g. Table[:title, :username]. ' \
                         "For every column of the repository's table, name the table, e.g. Posts"
    OPERATORS = %i[+ & < > <=> ^ * /].freeze

    # A bare table on its own is every column, as a data expression: `Users[:username] + Posts`.
    def self.expression(value) = value.is_a?(TableReference) ? value.to_expression : value

    attr_reader :table, :filter, :negated

    def initialize(table:, inverted: false, filter: DataExpression::Filter.new, negated: false)
      @table = table
      @inverted = inverted
      @filter = filter
      @negated = negated
    end

    # Each argument's type decides its meaning:
    #   Posts[:title]                              # A symbol is a column. Empty brackets select no columns.
    #   Users[:username, Posts[:title]]            # A data expression is a nested table, and a bare table nests
    #   Users[:username, Posts]                    # every column.
    #   Reviews[:rating, author: Users[:username]] # A keyword with a data expression names a nested table.
    #   Posts[:id, headline: :title]               # A keyword with a symbol renames a column.
    def [](*arguments, **keywords)
      check_negated!
      return inverted(arguments:, keywords:) if @inverted

      arguments = arguments.map { |argument| TableReference.expression(argument) }
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
    #   Posts(:user_id)                            # A symbol names the foreign key a nested join links by.
    def where(*arguments, **keywords, &block)
      related = arguments.grep_v(Symbol).map { |argument| related(key: nil, reference: argument) }
      values = {}

      keywords.each do |key, value|
        if key.is_a?(TableReference) then related << related(key: nil, reference: key, count: value)
        elsif value.is_a?(TableReference) then related << related(key:, reference: value)
        else values[key] = value
        end
      end

      conditions = block ? [Sequel.virtual_row(&block)] : []
      with(filter: filter.merge(DataExpression::Filter.new(values:, conditions:, related:, foreign_keys: arguments.grep(Symbol))))
    end

    # `~Posts` keeps rows without related posts.
    def ~
      with(negated: !negated)
    end

    # A bare table reads and joins as every column of the table:
    #   Posts                          # SELECT posts.* FROM posts
    #   Users[:username] + Posts       # Each user with every column of their posts.
    #   Posts ^ -Col[:views] * 10      # The 10 most viewed posts.
    def to_expression
      raise ArgumentError, BARE_TABLE_MESSAGE if @inverted

      check_negated!
      DataExpression.new(node: source)
    end

    OPERATORS.each do |operator|
      define_method(operator) { |other| to_expression.public_send(operator, other) }
    end

    %i[to_a sql dataset].each do |name|
      define_method(name) { |**options| to_expression.public_send(name, **options) }
    end

    def source
      DataExpression::Source.new(table:, columns: [], filter:, bare: true)
    end

    private

    def check_negated!
      raise ArgumentError, "~#{LowData.constant_name(table)} filters by related rows, so it can't select columns" if negated
    end

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
      keywords = keywords.transform_values { |value| TableReference.expression(value) }
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
      raise ArgumentError, BARE_TABLE_MESSAGE if arguments.empty? && keywords.empty?

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
