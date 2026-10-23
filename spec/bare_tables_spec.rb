# frozen_string_literal: true

require_relative '../lib/lowdata'
require 'logger'

require_relative 'helpers/database'

class BareTablesData < LowData
  self.table = :posts

  def every = Posts
  def every_filtered = Posts(views: 100..)
  def nest_every = Users[:username] + Posts
  def bracket_every = Users[:username, Posts]
  def named_every = Users[:username, written: Posts]
  def siblings = Posts[:title] + [Comments, Likes]
  def sorted = Posts ^ -Col[:views] * 1
  def paged = (Posts / 2)[1]
  def left_sorted = (Users < Posts) ^ Col[:username]
  def joined_without_columns = Users[] & Posts[:title]
  def nested_without_columns = Users[:username, Posts[]]
  def nested_join_without_columns = Users[:username] + (Posts[] & Comments[:body])
  def none = Posts[]
  def none_first = Posts[] + Users[:username]
  def none_joined = Users[] & Posts[]
  def bare_table = Table
  def empty_table = Table[]
  def negated = ~Posts
  def insert_none(post) = Posts[] << post
  def upsert_none(name) = Tags(name:)[] <= {}
end

RSpec.describe 'Bare tables select every column, and empty brackets select none' do
  subject(:repository) { BareTablesData.new }

  include_context 'with a database'

  let(:hello) { { id: 1, user_id: 1, title: 'Hello', views: 10 } }

  describe 'a bare table' do
    it 'selects every column' do
      expect(repository.every.sql).to eq('SELECT `posts`.* FROM `posts`')
      expect(repository.every.to_a.first).to eq(hello)
    end

    it 'selects every column of filtered rows' do
      expect(repository.every_filtered.to_a).to eq([{ id: 2, user_id: 2, title: 'World', views: 200 }])
    end

    it 'nests every column after +' do
      expect(repository.nest_every.to_a.first).to eq({ username: 'alice', posts: [hello] })
    end

    it 'nests every column in square brackets, with or without a name' do
      expect(repository.bracket_every.to_a.first).to eq({ username: 'alice', posts: [hello] })
      expect(repository.named_every.to_a.first).to eq({ username: 'alice', written: [hello] })
    end

    it 'nests side by side' do
      expect(repository.siblings.to_a.first).to eq(
        { title: 'Hello', comments: [{ id: 1, post_id: 1, body: 'Nice' }],
          likes: [{ id: 1, post_id: 1, user_id: 2 }, { id: 2, post_id: 1, user_id: 3 }] }
      )
    end

    it 'sorts, limits and pages' do
      expect(repository.sorted.to_a).to eq([{ id: 2, user_id: 2, title: 'World', views: 200 }])
      expect(repository.paged.to_a).to eq([{ id: 3, user_id: nil, title: 'Orphan', views: nil }])
    end

    it 'joins' do
      expect(repository.left_sorted.sql).to eq(
        'SELECT `users`.*, `posts`.* FROM `users` LEFT JOIN `posts` ON (`posts`.`user_id` = `users`.`id`) ORDER BY `users`.`username`'
      )
    end
  end

  describe 'empty brackets' do
    it 'select no columns in a join, which still links and filters rows' do
      expect(repository.joined_without_columns.sql)
        .to eq('SELECT `posts`.`title` FROM `users` INNER JOIN `posts` ON (`posts`.`user_id` = `users`.`id`)')
      expect(repository.joined_without_columns.to_a).to eq([{ title: 'Hello' }, { title: 'World' }])
    end

    it 'nest an empty hash for each related row' do
      expect(repository.nested_without_columns.to_a).to eq(
        [{ username: 'alice', posts: [{}] }, { username: 'bob', posts: [{}] }, { username: 'carol', posts: [] }]
      )
    end

    it "leave a nested join's rows to the other tables' columns" do
      expect(repository.nested_join_without_columns.to_a.first).to eq({ username: 'alice', posts: [{ body: 'Nice' }] })
    end

    it 'raise on their own, as the first table or when no table selects columns' do
      message = 'Empty brackets select no columns, so Posts[] returns nothing. Write Posts for every column, or name them, ' \
                'e.g. Posts[:id]'

      expect { repository.none.to_a }.to raise_error(ArgumentError, message)
      expect { repository.none_first.to_a }.to raise_error(ArgumentError, message)
      expect { repository.none_joined.to_a }.to raise_error(ArgumentError, /so Users\[\] returns nothing/)
    end

    it 'return an empty hash from a write' do
      expect(repository.insert_none({ title: 'New' })).to eq({})
      expect(database[:posts][id: 4]).to include(title: 'New')
    end

    it 'return an empty hash from an upsert' do
      database.add_index(:tags, :name, unique: true)

      expect(repository.upsert_none('ruby')).to eq({})
      expect(database[:tags].select_map(:name)).to eq(['ruby'])
    end

    it 'insert rows with the same columns in one INSERT' do
      inserts = []
      logger = Logger.new(nil)
      logger.define_singleton_method(:info) { |sql| inserts << sql if sql.include?('INSERT') }
      database.loggers << logger

      expect(repository.insert_none([{ title: 'One' }, { title: 'Two' }])).to eq([{}, {}])
      expect(inserts.length).to eq(1)
      expect(database[:posts].where(id: [4, 5]).select_map(:title)).to eq(%w[One Two])
    end

    it 'insert rows with different columns one by one, keeping every column' do
      repository.insert_none([{ title: 'One' }, { title: 'Two', views: 5 }])

      expect(database[:posts][id: 5]).to include(title: 'Two', views: 5)
    end
  end

  describe 'Table' do
    it "raises on its own and with empty brackets, since it joins by the columns it's given" do
      expect { repository.bare_table.to_a }.to raise_error(ArgumentError, /name them, e.g. Table\[:title, :username\]/)
      expect { repository.empty_table }.to raise_error(ArgumentError, /name them, e.g. Table\[:title, :username\]/)
    end
  end

  it 'keeps ~ as a filter only' do
    expect { repository.negated.to_a }.to raise_error(ArgumentError, "~Posts filters by related rows, so it can't select columns")
  end
end
