# frozen_string_literal: true

class LowData
  class Error < StandardError; end

  class ConfigError < Error
    MISSING_DATABASE = 'Set LowData.database to a Sequel database, e.g. LowData.database = Sequel.sqlite'
  end

  class JoinError < Error; end
end
