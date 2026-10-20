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

  describe '+' do
    it 'nests the table a row points to as an object named after the foreign key' do
      expect(repository.nest_one.to_a).to contain_exactly(
        { title: 'Hello', user: { username: 'alice' } },
        { title: 'World', user: { username: 'bob' } },
        { title: 'Orphan', user: nil }
      )
    end

    it 'nests the tables pointing to a row as an array named after the table' do
      expect(repository.nest_many.to_a).to contain_exactly(
        { username: 'alice', posts: [{ title: 'Hello' }] },
        { username: 'bob', posts: [{ title: 'World' }] },
        { username: 'carol', posts: [] }
      )
    end

    it 'nests chains through each foreign key' do
      expect(repository.nest_chain.to_a).to contain_exactly(
        { username: 'alice', posts: [{ title: 'Hello', comments: [{ body: 'Nice' }] }] },
        { username: 'bob', posts: [{ title: 'World', comments: [] }] },
        { username: 'carol', posts: [] }
      )
    end

    it 'nests by foreign key whatever order the tables after the subject are written in' do
      expect(repository.nest_chain_reordered.to_a).to match_array(repository.nest_chain.to_a)
    end

    it 'nests up through the tables a row points to' do
      expect(repository.nest_up.to_a).to contain_exactly(
        { body: 'Nice', post: { title: 'Hello', user: { username: 'alice' } } },
        { body: 'Spam', post: nil }
      )
    end

    it 'nests sibling tables without multiplying rows' do
      expect(repository.nest_siblings.to_a).to contain_exactly(
        { title: 'Hello', comments: [{ body: 'Nice' }], likes: [{ id: 1 }, { id: 2 }] },
        { title: 'World', comments: [], likes: [] },
        { title: 'Orphan', comments: [], likes: [] }
      )
    end

    it 'returns every column when none are given' do
      expect(repository.nest_all_columns.to_a).to include({ id: 1, user_id: 1, title: 'Hello', views: 10, user: { username: 'alice' } })
    end

    it 'runs one query per table' do
      queries = []
      logger = Object.new
      logger.define_singleton_method(:info) { |message| queries << message if message.include?('SELECT') }
      database.loggers << logger

      repository.nest_chain.to_a

      expect(queries.length).to eq(3)
    end

    it 'raises for SQL because it runs more than one query' do
      expect { repository.nest_chain.sql }.to raise_error(LowData::Error, /no single SQL query/)
    end

    it 'raises when foreign keys link the tables by more than one path' do
      expect { repository.nest_multiple_paths.to_a }.to raise_error(LowData::JoinError, /more than one path/)
    end

    it 'raises when no foreign key links the tables' do
      expect { repository.nest_unlinked.to_a }.to raise_error(LowData::JoinError, /No foreign key links tags to users/)
    end

    it 'raises when more than one foreign key links the tables' do
      expect { repository.nest_many_keys.to_a }.to raise_error(LowData::JoinError, /More than one foreign key links reviews and users/)
    end

    it 'raises on a self join' do
      expect { repository.nest_self.to_a }.to raise_error(LowData::JoinError, /Can't join users to itself/)
    end

    it 'raises when combined with other joins' do
      expect { repository.nest_then_left.sql }.to raise_error(LowData::JoinError, /can't be combined/)
      expect { repository.nest_after_join.to_a }.to raise_error(LowData::JoinError, /can't be combined/)
    end

    it 'raises when combined with Table[]' do
      expect { repository.nest_inverted.to_a }.to raise_error(LowData::JoinError, /Table\[\] can't be joined/)
    end

    it 'keeps every post flat with explicit joins' do
      expect(repository.explicit_posts.to_a).to contain_exactly(
        { username: 'alice', title: 'Hello', body: 'Nice' },
        { username: 'bob', title: 'World', body: nil },
        { username: nil, title: 'Orphan', body: nil }
      )
    end
  end

  describe 'brackets' do
    it 'nests a table in brackets the same as +' do
      expect(repository.bracket_one.to_a).to match_array(repository.nest_one.to_a)
      expect(repository.bracket_many.to_a).to match_array(repository.nest_many.to_a)
    end

    it 'nests directly under the table whose brackets it is in' do
      expect(repository.bracket_deep.to_a).to contain_exactly(
        { username: 'alice', posts: [{ title: 'Hello', likes: [{ id: 1 }, { id: 2 }] }] },
        { username: 'bob', posts: [{ title: 'World', likes: [] }] },
        { username: 'carol', posts: [] }
      )
    end

    it 'groups a + chain with parentheses' do
      expect(repository.grouped.to_a).to match_array(repository.bracket_deep.to_a)
    end

    it 'combines brackets and + in either direction' do
      expected = [
        { title: 'Hello', comments: [{ body: 'Nice' }], user: { username: 'alice' } },
        { title: 'World', comments: [], user: { username: 'bob' } },
        { title: 'Orphan', comments: [], user: nil }
      ]

      expect(repository.bracket_in_chain.to_a).to match_array(expected)
      expect(repository.chain_in_bracket.to_a).to include(
        { username: 'alice', posts: [{ title: 'Hello', comments: [{ body: 'Nice' }] }] }
      )
    end

    it 'picks the foreign key from the name on the "one" side' do
      expect(repository.named_one.to_a).to eq(
        [{ rating: 5, author: { username: 'alice' }, editor: { username: 'bob' } }]
      )
    end

    it 'renames the nested key on the "many" side' do
      expect(repository.named_many.to_a).to include({ username: 'alice', written: [{ title: 'Hello' }] })
    end

    it 'raises with a suggestion when a name matches no foreign key' do
      expect { repository.named_unmatched.to_a }.to raise_error(
        LowData::JoinError, /More than one foreign key links reviews and users. Name the one to follow, e.g. author: Users\[\] or editor/
      )
    end

    it 'raises when two nested tables have the same key' do
      expect { repository.duplicate_keys.to_a }.to raise_error(LowData::JoinError, /Two tables nest in users as posts/)
    end

    it 'raises when combined with other joins' do
      expect { repository.bracket_in_join.sql }.to raise_error(LowData::JoinError, /can't be combined/)
    end

    it 'raises for columns that are not symbols' do
      expect { Class.new(LowData).const_missing(:Posts)['title'] }.to raise_error(ArgumentError, /Columns are symbols/)
    end

    it 'raises for filters on Table[]' do
      expect { PostsData.const_missing(:Table)[:title, views: 1] }.to raise_error(ArgumentError, /column names only/)
    end
  end

  describe 'filters' do
    it 'filters by a range' do
      expect(repository.filter_range.sql).to eq('SELECT `posts`.`title` FROM `posts` WHERE (`posts`.`views` >= 100)')
      expect(repository.filter_upper.to_a).to eq([{ title: 'Hello' }])
    end

    it 'filters by a list of values' do
      expect(repository.filter_in.to_a).to contain_exactly({ title: 'Hello' }, { title: 'Orphan' })
    end

    it 'filters by nil' do
      expect(repository.filter_nil.to_a).to eq([{ title: 'Orphan' }])
    end

    it 'puts filters on joined tables in the WHERE clause' do
      expect(repository.filter_joined.sql).to eq(
        'SELECT `users`.`username`, `posts`.`title` FROM `users` INNER JOIN `posts` ON (`posts`.`user_id` = `users`.`id`) ' \
        'WHERE (`posts`.`views` >= 100)'
      )
    end

    it 'filters the nested rows, not the parents' do
      expect(repository.filter_nested.to_a).to contain_exactly(
        { username: 'alice', posts: [] },
        { username: 'bob', posts: [{ title: 'World' }] },
        { username: 'carol', posts: [] }
      )
    end

    it 'filters the subject' do
      expect(repository.filter_subject.to_a).to eq([{ username: 'alice', posts: [{ title: 'Hello' }] }])
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
