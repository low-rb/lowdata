# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'
require_relative 'fixtures/renamed_posts_data'

RSpec.describe 'Renaming columns with name: :column' do
  subject(:repository) { RenamedPostsData.new }

  include_context 'with a database'

  it 'returns a column under a new name' do
    expect(repository.renamed.sql).to eq('SELECT `posts`.`id`, `posts`.`title` AS \'headline\' FROM `posts`')
    expect(repository.renamed.to_a).to include({ id: 1, headline: 'Hello' })
  end

  it 'counts a rename as a column, so only it is selected' do
    expect(repository.only.to_a).to contain_exactly({ headline: 'Hello' }, { headline: 'World' }, { headline: 'Orphan' })
  end

  it 'keeps columns that joined tables share' do
    expect(repository.joined.to_a).to contain_exactly(
      { username: 'alice', user_id: 1, title: 'Hello', post_id: 1 },
      { username: 'bob', user_id: 2, title: 'World', post_id: 2 }
    )
  end

  it 'renames columns of nested tables and their parents' do
    expect(repository.nested.to_a).to contain_exactly(
      { handle: 'alice', posts: [{ headline: 'Hello' }] },
      { handle: 'bob', posts: [{ headline: 'World' }] },
      { handle: 'carol', posts: [] }
    )
  end

  it 'renames columns in nested joins and under joins' do
    expect(repository.nested_join.to_a).to include({ username: 'alice', posts: [{ headline: 'Hello', body: 'Nice' }] })
    expect(repository.under_join.to_a).to contain_exactly(
      { handle: 'alice', title: 'Hello', comments: [{ body: 'Nice' }] },
      { handle: 'bob', title: 'World', comments: [] }
    )
  end

  it 'sorts by the column, not the new name' do
    expect(repository.sorted.to_a.map { |row| row[:headline] }).to eq(%w[World Orphan Hello])
  end

  it 'renames columns in Table[]' do
    expect(repository.inverted.sql).to eq(
      'SELECT `posts`.`title`, `users`.`username` AS \'author\' FROM `posts` LEFT JOIN `users` ON (`posts`.`user_id` = `users`.`id`)'
    )
    expect(repository.inverted.to_a).to include({ title: 'Hello', author: 'alice' })
  end

  it 'raises with the fix when written backwards' do
    expect { repository.backwards.sql }.to raise_error(
      ArgumentError, 'posts has no headline column. To rename title, write headline: :title'
    )
    expect { repository.inverted_backwards.sql }.to raise_error(
      ArgumentError, 'No table related to posts has a author column. To rename username, write author: :username'
    )
  end

  it 'raises when the column is missing' do
    expect { repository.missing.sql }.to raise_error(ArgumentError, 'posts has no missing column to rename')
  end

  it 'raises when the table already has a column with the new name' do
    expect { repository.existing.sql }.to raise_error(
      ArgumentError, "posts already has a title column, so views can't be renamed to it"
    )
  end

  it 'raises when a name is used twice' do
    expect { repository.twice }.to raise_error(ArgumentError, 'Posts[] returns views twice. Name each value once')
  end

  it 'raises when a nested table has the same name' do
    expect { repository.nested_clash.to_a }.to raise_error(
      LowData::JoinError, 'posts returns user as both a renamed column and a nested table. Rename one'
    )
  end
end
