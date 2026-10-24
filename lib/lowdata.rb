# frozen_string_literal: true

require 'expressions'
require 'lowtype'
require 'sequel'

require_relative 'version'
require_relative 'errors'
require_relative 'data_expression'
require_relative 'data_expression/source'
require_relative 'rows'
require_relative 'col'
require_relative 'order_compiler'
require_relative 'filter_compiler'
require_relative 'schema'
require_relative 'inversion'
require_relative 'nested_join'
require_relative 'nesting'
require_relative 'nesting_tree'
require_relative 'nesting_path'
require_relative 'query_compiler'
require_relative 'writer'
require_relative 'data_expression/writes'
require_relative 'table_reference'
require_relative 'table_reference/writes'

class LowData
  class << self
    attr_reader :database
    attr_writer :table

    def database=(database)
      @database = database
      @tables = nil
    end

    # The database's tables, cached until the database changes.
    def tables
      @tables ||= database.tables
    end

    # The repository's table, named after the class: PostsData is :posts and BlogPostsData is :blog_posts.
    def table
      @table ||= name && table_name(name.split('::').last.delete_suffix('Data'))
    end

    # The Method Factory pattern, as in LowNode: each public instance method gets a class method of the same name, so
    # `UsersData.update(1, attributes)` calls `UsersData.new.update(1, attributes)`. Defined when the instance method
    # is, so it's a real method rather than a method_missing lookup. LowData's own class methods, like `table`, are kept.
    def method_added(name)
      super
      return if self == LowData || !public_method_defined?(name) || respond_to?(name, true)
      return unless name.match?(/\A[a-z_]\w*[?!]?\z/) # Setters like `title=` stay instance methods.

      singleton_class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def #{name}(...) = new.#{name}(...) # def update(...) = new.update(...)
      RUBY
    end

    # Resolve undefined constants in a repository to tables, so `Users` and `BlogPosts` become :users and :blog_posts.
    # `Table` is the repository's own table, joined to whichever related tables own the columns asked for.
    def const_missing(name)
      return super if self == LowData
      return inverted_table if name == :Table

      TableReference.new(table: table_name(name))
    end

    # The constant a table is written as in a data expression: :blog_posts is BlogPosts.
    def constant_name(table)
      table.to_s.split('_').map(&:capitalize).join
    end

    def table_name(constant_name)
      constant_name.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.to_sym
    end

    private

    def inverted_table
      raise ConfigError, "Set the table for #{self}, e.g. self.table = :posts" if table.nil?

      TableReference.new(table:, inverted: true)
    end
  end

  # Round brackets after a table filter it: `Posts(published: true) { views > 100 }[:title]`. A capitalised name is a
  # table only when the database has that table, so typos still raise NoMethodError. `Table(...)` is always a table.
  def method_missing(name, *arguments, **keywords, &block)
    return super unless name.match?(/\A[A-Z]/)
    raise ConfigError, ConfigError::MISSING_DATABASE if LowData.database.nil?

    # Raised rather than left to super, which can report a NameError instead when looking up the tables runs a
    # method_missing of its own, as Postgres' adapter does.
    raise NoMethodError.new("undefined method '#{name}' for an instance of #{self.class}", name) unless table_method?(name:)

    self.class.const_missing(name).where(*arguments, **keywords, &block)
  end

  def respond_to_missing?(name, include_private = false)
    table_method?(name:) || super
  end

  private

  def table_method?(name:)
    return false unless name.match?(/\A[A-Z]/)
    return true if name == :Table
    return false if LowData.database.nil?

    LowData.tables.include?(LowData.table_name(name))
  end
end
