# frozen_string_literal: true

require 'expressions'
require 'lowtype'
require 'sequel'

require_relative 'version'
require_relative 'errors'
require_relative 'data_expression'
require_relative 'query_compiler'
require_relative 'table_reference'

class LowData
  class << self
    attr_accessor :database

    # Resolve undefined constants in a repository to tables, so `Users` and `BlogPosts` become :users and :blog_posts.
    def const_missing(name)
      return super if self == LowData

      TableReference.new(table: table_name(name))
    end

    private

    def table_name(constant_name)
      constant_name.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.to_sym
    end
  end
end
