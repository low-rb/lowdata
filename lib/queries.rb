# frozen_string_literal: true

class LowData
  # Include in a module of queries that repositories share, so its tables and Col are found as they are in a
  # repository. Ruby looks a constant up where its method is written, so without this `Users` in the module isn't a table:
  #
  #   module LatestQueries
  #     include LowData::Queries
  #
  #     def latest(count: 10) = Table(published: true)[:title, :username] ^ -Col[:created_at] * count
  #   end
  #
  #   class PostsData < LowData
  #     include LatestQueries # PostsData.latest, like the repository's own methods
  #   end
  module Queries
    def self.included(queries)
      queries.extend(Tables)
    end

    # Resolves the module's undefined constants to tables, as LowData.const_missing does in a repository. `Table` is the
    # repository's own table, so it's written `Table(...)`, a method call that's resolved in the repository.
    module Tables
      def const_missing(name)
        return LowData::Col if name == :Col
        raise NameError, "Write Table(...) in #{self}, as it's the table of the repository that includes it" if name == :Table

        LowData::TableReference.new(table: LowData.table_name(name))
      end
    end
  end
end
