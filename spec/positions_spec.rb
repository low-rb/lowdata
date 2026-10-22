# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'
require_relative 'fixtures/positions_data'

RSpec.describe 'Nesting and joining by position' do
  subject(:repository) { PositionsData.new }

  include_context 'with a database'

  describe '+' do
    it 'groups with parentheses without changing the path' do
      expect(repository.grouped.to_a).to match_array(repository.chain.to_a)
    end

    it 'nests an array side by side in the table before it, with paths as elements' do
      expect(repository.siblings_with_path.to_a).to contain_exactly(
        { username: 'alice', posts: [{ title: 'Hello', comments: [{ body: 'Nice' }] }], likes: [] },
        { username: 'bob', posts: [{ title: 'World', comments: [] }], likes: [{ id: 1 }] },
        { username: 'carol', posts: [], likes: [{ id: 2 }] }
      )
    end

    it 'suggests an array or a named foreign key when a table links to an earlier one' do
      expect { repository.siblings_chained.to_a }.to raise_error(
        LowData::JoinError,
        'No foreign key links likes to comments. To nest likes in posts, beside comments, write Posts + [Comments, Likes] ' \
        'or name its foreign key: Likes(:post_id)'
      )
    end

    it 'sorts and limits one element of an array' do
      expect(repository.siblings_sorted.to_a).to include({ username: 'bob', posts: [{ title: 'World' }], likes: [{ id: 1 }] })
    end

    it 'raises when the chain continues after an array' do
      expect { repository.after_array.to_a }.to raise_error(LowData::JoinError, /An array ends a \+ chain/)
    end

    it 'raises for an array of values' do
      expect { repository.array_of_values }.to raise_error(ArgumentError, /Nest data expressions such as Comments\[:body\], not :body/)
    end

    it 'reaches back to an earlier table by a named foreign key' do
      expect(repository.reach_back.to_a).to contain_exactly(
        { username: 'alice', posts: [{ title: 'Hello', comments: [{ body: 'Nice' }] }], likes: [] },
        { username: 'bob', posts: [{ title: 'World', comments: [] }], likes: [{ id: 1 }] },
        { username: 'carol', posts: [], likes: [{ id: 2 }] }
      )
    end

    it 'raises when a named foreign key points outside the chain' do
      expect { repository.reach_back_outside.to_a }.to raise_error(
        LowData::JoinError, "likes.user_id points to users, which isn't earlier in this + chain"
      )
    end
  end

  it 'ignores a foreign key named between the tables of a nested join' do
    expect(repository.named_in_join.to_a).to match_array(repository.join_in_chain.to_a)
  end

  describe 'joins' do
    it 'joins each table to the table before it, ignoring foreign keys to tables further back' do
      expect(repository.join_adjacent.sql).to include('INNER JOIN `likes` ON (`likes`.`post_id` = `posts`.`id`)')
    end

    it 'suggests a named foreign key when a table links to an earlier one' do
      expect { repository.join_unlinked.sql }.to raise_error(
        LowData::JoinError,
        'No foreign key links reviews to posts, the table before it. To join it to an earlier table, name the foreign key: ' \
        'Reviews(:author_id) or Reviews(:editor_id)'
      )
    end

    it 'reaches back to an earlier table by a named foreign key' do
      expect(repository.join_reach_back.sql).to include('INNER JOIN `reviews` ON (`reviews`.`author_id` = `users`.`id`)')
      expect(repository.join_reach_back.to_a).to contain_exactly({ username: 'alice', title: 'Hello', rating: 5 })
    end
  end
end
