# frozen_string_literal: true

require 'expressions'
require 'lowtype'
require 'sequel'

require_relative 'version'
require_relative 'errors'
require_relative 'data_expression'
require_relative 'schema'
require_relative 'inversion'
require_relative 'lookup'
require_relative 'query_compiler'
require_relative 'table_reference'

class LowData
  class << self
    attr_accessor :database
    attr_writer :table

    # The repository's table, named after the class: PostsData is :posts and BlogPostsData is :blog_posts.
    def table
      @table ||= name && table_name(name.split('::').last.delete_suffix('Data'))
    end

    # Resolve undefined constants in a repository to tables, so `Users` and `BlogPosts` become :users and :blog_posts.
    # `Table` is the repository's own table, joined to whichever related tables own the columns asked for.
    def const_missing(name)
      return super if self == LowData
      return inverted_table if name == :Table

      TableReference.new(table: table_name(name))
    end

    private

    def inverted_table
      raise ConfigError, "Set the table for #{self}, e.g. self.table = :posts" if table.nil?

      TableReference.new(table:, inverted: true)
    end

    def table_name(constant_name)
      constant_name.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.to_sym
    end
  end
end
