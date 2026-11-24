# frozen_string_literal: true

require 'lowevent'

class LowData
  # A query the database runs. Recording it times the query in the tree of the request or interval that ran it.
  class DataEvent < LowEvent
    def initialize
      super(key: DataEvent, action: :query)
    end
  end

  # A Sequel extension that records each query the database runs as a DataEvent. LowData adds it to its database.
  module DataEvents
    def log_connection_yield(sql, connection, args = nil)
      DataEvent.new.record { super }
    end
  end
end

Sequel::Database.register_extension(:lowdata_events, LowData::DataEvents)
