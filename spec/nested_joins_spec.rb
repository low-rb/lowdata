# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'
require_relative 'fixtures/nested_joins_data'

RSpec.describe 'Nesting joins with +' do
  subject(:repository) { NestedJoinsData.new }

  include_context 'with a database'

  it 'nests the joined rows as an array under the table that links to the parent' do
    expect(repository.nest_join.to_a).to contain_exactly(
      { username: 'alice', posts: [{ title: 'Hello', body: 'Nice' }] },
      { username: 'bob', posts: [] },
      { username: 'carol', posts: [] }
    )
  end

  it 'keeps the rows the join keeps' do
    expect(repository.nest_left_join.to_a).to include({ username: 'bob', posts: [{ title: 'World', body: nil }] })
  end

  it 'links through whichever joined table links to the parent' do
    expect(repository.nest_join_reordered.to_a).to include({ username: 'alice', posts: [{ body: 'Nice', title: 'Hello' }] })
  end

  it 'loads the join with one query' do
    queries = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| queries << message if message.include?('SELECT') }
    database.loggers << logger

    repository.nest_join.to_a

    expect(queries.length).to eq(2)
    expect(queries.last).to include('INNER JOIN `comments`')
  end

  it 'sorts and limits the joined rows per parent' do
    database[:comments].insert(id: 3, post_id: 1, body: 'Again')

    expect(repository.nest_join_sorted.to_a).to include(
      { username: 'alice', posts: [{ title: 'Hello', body: 'Nice' }, { title: 'Hello', body: 'Again' }] }
    )
    expect(repository.nest_join_limited.to_a).to include({ username: 'alice', posts: [{ title: 'Hello', body: 'Again' }] })
  end

  it 'sorts the parents with a sort outside the parentheses' do
    expect { repository.nest_join_sorted_outside.to_a }.to raise_error(LowData::JoinError, /No table in users has a body column/)
  end

  it 'filters the joined rows' do
    expect(repository.nest_join_filtered.to_a).to include(
      { username: 'alice', posts: [] },
      { username: 'bob', posts: [{ title: 'World', body: nil }] }
    )
  end

  it 'nests a join in brackets, under a name' do
    expect(repository.nest_join_in_brackets.to_a).to match_array(repository.nest_join.to_a)
    expect(repository.nest_join_named.to_a).to include({ username: 'alice', written: [{ title: 'Hello', body: 'Nice' }] })
  end

  it 'raises on the "one" side, where joined rows can repeat the linked row' do
    expect { repository.nest_join_one_side.to_a }.to raise_error(LowData::JoinError, /comments points to posts/)
  end

  it 'raises when more than one joined table links to the parent' do
    expect { repository.nest_join_both_link.to_a }.to raise_error(
      LowData::JoinError,
      "posts and likes both link to users, so the join can't nest in users by a single foreign key. " \
      'Name the foreign key to nest by in round brackets: Posts(:user_id) or Likes(:user_id)'
    )
  end

  it 'links by the foreign key named in round brackets when more than one table links' do
    expect(repository.nest_join_foreign_key.to_a).to contain_exactly(
      { username: 'alice', posts: [{ title: 'Hello', id: 1 }, { title: 'Hello', id: 2 }] },
      { username: 'bob', posts: [] },
      { username: 'carol', posts: [] }
    )
    expect(repository.nest_join_other_foreign_key.to_a).to contain_exactly(
      { username: 'alice', likes: [] },
      { username: 'bob', likes: [{ title: 'Hello', id: 1 }] },
      { username: 'carol', likes: [{ title: 'Hello', id: 2 }] }
    )
  end

  it 'raises when a joined table has no foreign key' do
    expect { repository.nest_join_unlinked.to_a }.to raise_error(LowData::JoinError, /No foreign key links tags/)
  end

  it 'nests tables under each joined row' do
    expect(repository.nest_after_join.to_a).to contain_exactly(
      { username: 'alice', title: 'Hello', comments: [{ body: 'Nice' }] },
      { username: 'bob', title: 'World', comments: [] }
    )
  end

  it 'nests the table a joined row points to as an object' do
    expect(repository.nest_under_join_one.to_a).to eq([{ title: 'Hello', body: 'Nice', user: { username: 'alice' } }])
  end

  it 'sorts the joined rows that tables nest under' do
    expect(repository.nest_under_join_sorted.to_a.map { |row| row[:title] }).to eq(%w[World Hello])
  end

  it 'loads the join and each table under it with one query each' do
    queries = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| queries << message if message.include?('SELECT') }
    database.loggers << logger

    repository.nest_after_join.to_a

    expect(queries.length).to eq(2)
  end

  it 'raises when more than one joined table links to the nested table' do
    expect { repository.nest_under_join_both_link.to_a }.to raise_error(
      LowData::JoinError,
      "users and posts both link to likes, so likes can't nest in the join by a single foreign key. " \
      'Name the foreign key to nest by in round brackets: Likes(:user_id) or Likes(:post_id)'
    )
  end

  it 'links a table under a join by the foreign key named in round brackets' do
    expect(repository.nest_under_join_foreign_key.to_a).to contain_exactly(
      { username: 'alice', title: 'Hello', likes: [{ id: 1 }, { id: 2 }] },
      { username: 'bob', title: 'World', likes: [] }
    )
  end

  it 'raises when the join holds nested tables' do
    expect { repository.nest_join_nested.to_a }.to raise_error(LowData::JoinError, /can't be combined/)
  end
end
