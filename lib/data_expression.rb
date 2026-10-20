# frozen_string_literal: true

class LowData
  # Joins tables with operators and builds a join tree for QueryCompiler:
  #   Users[:username] + Posts[:title] # Full outer join.
  #   Users[:username] & Posts[:title] # Inner join.
  #   Users[:username] < Posts[:title] # Left join.
  #   Users[:username] > Posts[:title] # Right join.
  class DataExpression < ::Expressions::Expression
    Source = ::Data.define(:table, :columns)
    Join = ::Data.define(:type, :left, :right)

    JOIN_HOOKS = { add: :full, intersect: :inner, lt: :left, gt: :right }.freeze

    attr_reader :node

    def initialize(table:, columns:)
      @node = Source.new(table:, columns:)
    end

    def dataset(database: LowData.database)
      QueryCompiler.new(database:).compile(node: @node)
    end

    def sql(database: LowData.database)
      dataset(database:).sql
    end

    def to_a(database: LowData.database)
      dataset(database:).all
    end

    private

    JOIN_HOOKS.each do |prefix, type|
      define_method(:"#{prefix}_expression") do |expression|
        @node = Join.new(type:, left: @node, right: expression.node)
      end

      define_method(:"#{prefix}_value") do |value|
        raise ArgumentError, "Join a data expression such as Posts[:title], not the value #{value.inspect}"
      end

      define_method(:"#{prefix}_type") do |type_|
        raise ArgumentError, "Join a data expression such as Posts[:title], not the type #{type_}"
      end
    end
  end
end
