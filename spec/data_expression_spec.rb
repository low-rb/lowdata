# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'fixtures/articles_data'
require_relative 'fixtures/posts_data'
require_relative 'fixtures/users_data'

RSpec.describe LowData::DataExpression do
  subject(:repository) { PostsData.new }

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

      db[:users].import(%i[id username], [[1, 'alice'], [2, 'bob'], [3, 'carol']])
      db[:posts].import(%i[id user_id title], [[1, 1, 'Hello'], [2, 2, 'World'], [3, nil, 'Orphan']])
      db[:comments].import(%i[id post_id body], [[1, 1, 'Nice'], [2, nil, 'Spam']])
    end
  end

  before { LowData.database = database }
  after { LowData.database = nil }

  describe '+' do
    it 'starts from the table holding the foreign key and left joins the table it points to' do
      expect(repository.lookup.sql).to eq(
        'SELECT `users`.`username`, `posts`.`title` FROM `posts` LEFT JOIN `users` ON (`posts`.`user_id` = `users`.`id`)'
      )
    end

    it 'returns every row of the subject once, in either order' do
      expected = [
        { username: 'alice', title: 'Hello' },
        { username: 'bob', title: 'World' },
        { username: nil, title: 'Orphan' }
      ]

      expect(repository.lookup.to_a).to match_array(expected)
      expect(repository.lookup_reversed.to_a).to match_array(expected)
    end

    it 'selects columns in the order the tables were written' do
      expect(repository.lookup_reversed.sql).to start_with('SELECT `posts`.`title`, `users`.`username` FROM `posts`')
    end

    it 'follows foreign keys up from the subject' do
      expect(repository.lookup_chained.sql).to eq(
        'SELECT `users`.`username`, `posts`.`title`, `comments`.`body` FROM `comments` ' \
        'LEFT JOIN `posts` ON (`comments`.`post_id` = `posts`.`id`) ' \
        'LEFT JOIN `users` ON (`posts`.`user_id` = `users`.`id`)'
      )
    end

    it 'returns every row of the subject once in any order' do
      expected = [
        { username: 'alice', title: 'Hello', body: 'Nice' },
        { username: nil, title: nil, body: 'Spam' }
      ]

      expect(repository.lookup_chained.to_a).to match_array(expected)
      expect(repository.lookup_chained_reversed.to_a).to match_array(expected)
      expect(repository.lookup_chained_middle.to_a).to match_array(expected)
    end

    it 'can be joined with other operators' do
      expect(repository.lookup_then_left.to_a).to contain_exactly(
        { username: 'alice', title: 'Hello', body: 'Nice' },
        { username: 'bob', title: 'World', body: nil },
        { username: nil, title: 'Orphan', body: nil }
      )
    end

    it 'keeps every post with explicit joins' do
      expect(repository.explicit_posts.to_a).to contain_exactly(
        { username: 'alice', title: 'Hello', body: 'Nice' },
        { username: 'bob', title: 'World', body: nil },
        { username: nil, title: 'Orphan', body: nil }
      )
    end

    it 'raises when two tables point to the same table' do
      expect { repository.lookup_shared.sql }.to raise_error(
        LowData::JoinError, /posts and reviews both point to users, so \+ has no single table to keep/
      )
    end

    it 'raises when no foreign key links the tables' do
      expect { repository.lookup_unlinked.sql }.to raise_error(LowData::JoinError, /No foreign key links users to tags/)
    end

    it 'raises when more than one foreign key links the tables' do
      expect { repository.lookup_many_keys.sql }.to raise_error(LowData::JoinError, /More than one foreign key/)
    end

    it 'raises on a self join' do
      expect { repository.lookup_self.sql }.to raise_error(LowData::JoinError, /Can't join users to itself/)
    end

    it 'raises when following other joins' do
      expect { repository.lookup_after_join.sql }.to raise_error(LowData::JoinError, /Put \+ joins first/)
    end
  end

  describe '<=>' do
    it 'builds a full outer join' do
      expect(repository.full.sql).to eq(
        'SELECT `users`.`username`, `posts`.`title` FROM `users` FULL JOIN `posts` ON (`posts`.`user_id` = `users`.`id`)'
      )
    end

    it 'keeps rows from both tables' do
      expect(repository.full.to_a).to contain_exactly(
        { username: 'alice', title: 'Hello' },
        { username: 'bob', title: 'World' },
        { username: 'carol', title: nil },
        { username: nil, title: 'Orphan' }
      )
    end
  end

  describe '&' do
    it 'builds an inner join' do
      expect(repository.inner.sql).to eq(
        'SELECT `users`.`username`, `posts`.`title` FROM `users` INNER JOIN `posts` ON (`posts`.`user_id` = `users`.`id`)'
      )
    end

    it 'keeps rows that match in both tables' do
      expect(repository.inner.to_a).to contain_exactly(
        { username: 'alice', title: 'Hello' },
        { username: 'bob', title: 'World' }
      )
    end
  end

  describe '<' do
    it 'builds a left join' do
      expect(repository.left.sql).to eq(
        'SELECT `users`.`username`, `posts`.`title` FROM `users` LEFT JOIN `posts` ON (`posts`.`user_id` = `users`.`id`)'
      )
    end

    it 'keeps every row from the left table' do
      expect(repository.left.to_a).to contain_exactly(
        { username: 'alice', title: 'Hello' },
        { username: 'bob', title: 'World' },
        { username: 'carol', title: nil }
      )
    end
  end

  describe '>' do
    it 'builds a right join' do
      expect(repository.right.sql).to eq(
        'SELECT `users`.`username`, `posts`.`title` FROM `users` RIGHT JOIN `posts` ON (`posts`.`user_id` = `users`.`id`)'
      )
    end

    it 'keeps every row from the right table' do
      expect(repository.right.to_a).to contain_exactly(
        { username: 'alice', title: 'Hello' },
        { username: 'bob', title: 'World' },
        { username: nil, title: 'Orphan' }
      )
    end
  end

  describe 'columns' do
    it 'selects every column when none are given' do
      expect(repository.all_columns.sql).to start_with('SELECT `users`.*, `posts`.* FROM')
    end
  end

  describe 'chaining' do
    it 'joins each table to any table already joined' do
      expect(repository.chained.sql).to eq(
        'SELECT `users`.`username`, `posts`.`title`, `comments`.`body` FROM `users` ' \
        'INNER JOIN `posts` ON (`posts`.`user_id` = `users`.`id`) ' \
        'INNER JOIN `comments` ON (`comments`.`post_id` = `posts`.`id`)'
      )
    end

    it 'joins mixed operators from the left when parenthesized' do
      expect(repository.parenthesized.to_a).to contain_exactly({ username: 'alice', title: 'Hello', body: 'Nice' })
    end

    it 'raises when Ruby precedence nests a join on the right' do
      expect { repository.nested.sql }.to raise_error(LowData::JoinError, /Add parentheses/)
    end
  end

  describe 'Table[]' do
    it 'joins the repository table to the tables that own each column' do
      expect(repository.inverted.sql).to eq(
        'SELECT `users`.`username`, `posts`.`title`, `comments`.`body` FROM `posts` ' \
        'LEFT JOIN `users` ON (`posts`.`user_id` = `users`.`id`) ' \
        'LEFT JOIN `comments` ON (`comments`.`post_id` = `posts`.`id`)'
      )
    end

    it 'keeps every row from the repository table' do
      expect(repository.inverted.to_a).to contain_exactly(
        { username: 'alice', title: 'Hello', body: 'Nice' },
        { username: 'bob', title: 'World', body: nil },
        { username: nil, title: 'Orphan', body: nil }
      )
    end

    it 'selects columns in the order given' do
      expect(repository.inverted_order.sql).to start_with('SELECT `posts`.`title`, `users`.`username` FROM `posts`')
    end

    it 'uses the table set on the repository' do
      expect(ArticlesData.new.all.sql).to eq('SELECT `posts`.`title` FROM `posts`')
    end

    it 'raises when a column is only on an unrelated table' do
      expect { repository.inverted_unrelated.sql }.to raise_error(LowData::JoinError, /No table related to posts has a name column/)
    end

    it 'raises when no table has the column' do
      expect { repository.inverted_missing.sql }.to raise_error(LowData::JoinError, /No table related to posts has a missing column/)
    end

    it 'raises when more than one related table has the column' do
      expect { UsersData.new.ambiguous.sql }.to raise_error(
        LowData::JoinError, /posts and reviews both have a title column.*Users\[\] < Posts\[:title\]/
      )
    end

    it 'raises when more than one foreign key links the owning table' do
      expect { UsersData.new.many_keys.sql }.to raise_error(LowData::JoinError, /More than one foreign key/)
    end

    it 'raises when joined with another expression' do
      expect { repository.inverted_join.sql }.to raise_error(LowData::JoinError, /Table\[\] can't be joined/)
    end
  end

  describe 'errors' do
    it 'raises when no foreign key links the tables' do
      expect { repository.unrelated.sql }.to raise_error(LowData::JoinError, /No foreign key links tags to users/)
    end

    it 'raises when more than one foreign key links the tables' do
      expect { repository.ambiguous.sql }.to raise_error(LowData::JoinError, /More than one foreign key/)
    end

    it 'raises on a self join' do
      expect { repository.self_join.sql }.to raise_error(LowData::JoinError, /Can't join users to itself/)
    end

    it 'raises when joined to a value' do
      expect { repository.value }.to raise_error(ArgumentError, /not the value :posts/)
    end

    it 'raises when joined to a type' do
      expect { repository.type }.to raise_error(ArgumentError, /not the type String/)
    end

    it 'raises without a database' do
      LowData.database = nil
      expect { repository.inner.sql }.to raise_error(LowData::ConfigError)
    end
  end
end
