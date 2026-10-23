# frozen_string_literal: true

require 'logger'
require 'sequel'
require 'stringio'

# The database specs run against: in-memory SQLite, or the database in DATABASE_URL, such as
#   DATABASE_URL=postgres://lowdata:lowdata@localhost/lowdata_test bundle exec rspec
#   DATABASE_URL=trilogy://lowdata:lowdata@127.0.0.1:3307/lowdata_test bundle exec rspec
# See compose.yaml to start them locally.
module SpecDatabase
  # Dropped in this order, so no table is dropped while another references it.
  TABLES = %i[likes reviews tags comments posts users].freeze

  class << self
    def connect
      return Sequel.sqlite if url.empty?

      # A server database is reused, and emptied before each example.
      @connection ||= Sequel.connect(url)
      @connection.drop_table?(*TABLES)
      @connection
    end

    def sqlite?
      url.empty? || url.start_with?('sqlite')
    end

    def url = ENV.fetch('DATABASE_URL', '')
  end

  # SQL text in specs is written in SQLite's dialect, so other databases generate it, which still raises for a broken
  # expression, but don't compare it. Their results are checked by the rest of each example.
  UncomparedSql = Struct.new(:sql) do
    def to(*) = nil
    def not_to(*) = nil
  end

  def expect_sql(sql)
    SpecDatabase.sqlite? ? expect(sql) : UncomparedSql.new(sql)
  end

  # Lookups of the schema itself, which LowData makes to find columns and foreign keys.
  CATALOG = /\b(pg_\w+|information_schema|sqlite_\w+|version\(\)|PRAGMA)\b/i

  # The SELECT statements the block runs on the database's tables, so a spec can count queries on any database.
  def queries
    log = StringIO.new
    logger = Logger.new(log, formatter: ->(_severity, _time, _program, message) { "#{message}\n" })
    database.loggers << logger
    yield
    log.string.lines.map { |line| line.sub(/\A\([\d.]+s\) /, '').chomp }.grep(/\ASELECT/).grep_v(CATALOG)
  ensure
    database.loggers.delete(logger)
  end
end

RSpec.configure { |config| config.include SpecDatabase }

# Users, posts, comments, tags, reviews and likes, set as LowData.database.
RSpec.shared_context 'with a database' do
  let(:database) do
    SpecDatabase.connect.tap do |db|
      db.create_table(:users) do
        primary_key :id
        String :username
      end
      db.create_table(:posts) do
        primary_key :id
        foreign_key :user_id, :users
        String :title
        Integer :views
      end
      db.create_table(:comments) do
        primary_key :id
        foreign_key :post_id, :posts
        String :body
      end
      db.create_table(:tags) do
        primary_key :id
        String :name
      end
      db.create_table(:reviews) do
        primary_key :id
        foreign_key :author_id, :users
        foreign_key :editor_id, :users
        Integer :rating
        String :title
      end

      db.create_table(:likes) do
        primary_key :id
        foreign_key :post_id, :posts
        foreign_key :user_id, :users
      end

      db[:users].import(%i[id username], [[1, 'alice'], [2, 'bob'], [3, 'carol']])
      db[:posts].import(%i[id user_id title views], [[1, 1, 'Hello', 10], [2, 2, 'World', 200], [3, nil, 'Orphan', nil]])
      db[:comments].import(%i[id post_id body], [[1, 1, 'Nice'], [2, nil, 'Spam']])
      db[:likes].import(%i[id post_id user_id], [[1, 1, 2], [2, 1, 3]])
      db[:reviews].import(%i[id author_id editor_id rating title], [[1, 1, 2, 5, 'Good']])

      # Postgres doesn't move a table's id sequence past ids inserted explicitly, so the next insert would reuse id 1.
      SpecDatabase::TABLES.each { |table| db.reset_primary_key_sequence(table) } if db.database_type == :postgres
    end
  end

  before { LowData.database = database }
  after { LowData.database = nil }
end
