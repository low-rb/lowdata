# frozen_string_literal: true

require 'sequel'

# An in-memory SQLite database with users, posts, comments, tags, reviews and likes, set as LowData.database.
RSpec.shared_context 'with a database' do
  let(:database) do
    Sequel.sqlite.tap do |db|
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
    end
  end

  before { LowData.database = database }
  after { LowData.database = nil }
end
