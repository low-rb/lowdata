# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'
require_relative 'fixtures/sorted_posts_data'

RSpec.describe 'Sorting with ^ Col[] and limiting with arithmetic' do
  subject(:repository) { SortedPostsData.new }

  include_context 'with a database'

  it 'sorts ascending by a column' do
    expect_sql(repository.sorted.sql).to eq('SELECT `posts`.`title` FROM `posts` ORDER BY `posts`.`views` ASC NULLS LAST')
    expect(repository.sorted.to_a).to eq([{ title: 'Hello' }, { title: 'World' }, { title: 'Orphan' }])
  end

  it 'sorts by several columns in the order written' do
    expect_sql(repository.sorted_many.sql).to end_with('ORDER BY `posts`.`user_id` ASC NULLS LAST, `posts`.`title` ASC NULLS LAST')
  end

  it 'sorts every column descending with -' do
    expect_sql(repository.sorted_desc.sql).to end_with('ORDER BY `posts`.`views` DESC NULLS LAST, `posts`.`title` DESC NULLS LAST')
    expect(repository.sorted_desc.to_a).to eq([{ title: 'World' }, { title: 'Hello' }, { title: 'Orphan' }])
  end

  it 'mixes directions with +' do
    expect(repository.sorted_mixed.to_a).to eq([{ title: 'World' }, { title: 'Hello' }, { title: 'Orphan' }])
  end

  it 'adds sort columns when sorting twice' do
    expect_sql(repository.sorted_twice.sql).to end_with('ORDER BY `posts`.`user_id` ASC NULLS LAST, `posts`.`title` DESC NULLS LAST')
  end

  it 'limits with *' do
    expect_sql(repository.limited.sql).to eq('SELECT `posts`.`title` FROM `posts` LIMIT 2')
    expect(repository.sorted_limited.to_a).to eq([{ title: 'World' }])
    expect(repository.sorted_then_limited.to_a).to eq([{ title: 'Hello' }, { title: 'World' }])
  end

  it 'picks rows with a range, counting from 0' do
    expect_sql(repository.ranged.sql).to end_with('ORDER BY `posts`.`id` ASC NULLS LAST LIMIT 2 OFFSET 1')
    expect(repository.ranged.to_a).to eq([{ title: 'World' }, { title: 'Orphan' }])
    expect(repository.ranged_endless.to_a).to eq([{ title: 'World' }, { title: 'Orphan' }])
  end

  it 'splits into pages with / and picks one with [], counting from 0' do
    expect(repository.paged(0).to_a).to eq([{ title: 'Hello' }, { title: 'World' }])
    expect_sql(repository.paged(1).sql).to end_with('LIMIT 2 OFFSET 2')
    expect(repository.paged(1).to_a).to eq([{ title: 'Orphan' }])
    expect(repository.paged(2).to_a).to eq([])
    expect_sql(repository.paged_unsorted.sql).to eq('SELECT `posts`.`title` FROM `posts` LIMIT 2')
  end

  it 'picks more than one page from the same pages' do
    pages = repository.pages
    expect([pages[0].to_a, pages[1].to_a]).to eq([[{ title: 'Hello' }, { title: 'World' }], [{ title: 'Orphan' }]])
  end

  it 'raises when a page is not picked' do
    expect { repository.paged_unpicked.to_a }.to raise_error(ArgumentError, /Pick a page/)
  end

  it 'sorts filtered rows' do
    expect(repository.sorted_filtered.to_a).to eq([{ title: 'World' }, { title: 'Hello' }])
  end

  it 'sorts the joined rows by the table that has the column' do
    expect_sql(repository.sorted_join.sql).to end_with('ORDER BY `posts`.`views` DESC NULLS LAST')
    expect(repository.sorted_join.to_a).to eq([{ username: 'bob', title: 'World' }, { username: 'alice', title: 'Hello' }])
  end

  it 'raises when more than one or no joined table has the column' do
    expect { repository.sorted_join_ambiguous.sql }.to raise_error(LowData::JoinError, /users and posts both have a id column/)
    expect { repository.sorted_join_missing.sql }.to raise_error(LowData::JoinError, /No table in users, posts has a missing column/)
  end

  it 'raises when a sort or limit lands inside a join' do
    expect { repository.sorted_left_join.sql }.to raise_error(LowData::JoinError, /Sort and limit after joining/)
    expect { repository.limited_join.sql }.to raise_error(LowData::JoinError, /Sort and limit after joining/)
  end

  it 'sorts a parenthesized join' do
    expect(repository.sorted_left_join_parenthesized.to_a.map { |row| row[:username] }).to eq(%w[alice bob carol])
  end

  it 'sorts Table[]' do
    expect(repository.sorted_inverted.to_a).to eq(
      [{ username: 'bob', title: 'World' }, { username: 'alice', title: 'Hello' }, { username: nil, title: 'Orphan' }]
    )
  end

  it 'sorts nested rows and their parents' do
    expect(repository.sorted_nested.to_a).to eq(
      [{ username: 'carol', posts: [] }, { username: 'bob', posts: [{ title: 'World' }] },
       { username: 'alice', posts: [{ title: 'Hello' }] }]
    )
  end

  it 'limits nested rows per parent' do
    expect(repository.limited_nested.to_a).to contain_exactly(
      { title: 'Hello', likes: [{ id: 2 }] },
      { title: 'World', likes: [] },
      { title: 'Orphan', likes: [] }
    )
    expect(repository.ranged_nested.to_a).to include({ title: 'Hello', likes: [{ id: 2 }] })
  end

  it 'limits a table in a + chain per parent' do
    expect(repository.limited_chain.to_a).to contain_exactly(
      { username: 'alice', likes: [] },
      { username: 'bob', likes: [{ id: 1 }] },
      { username: 'carol', likes: [{ id: 2 }] }
    )
  end

  it 'sorts the first table of a + chain' do
    expect(repository.sorted_chain.to_a.map { |row| row[:username] }).to eq(%w[carol bob alice])
  end

  it 'raises for sorts without Col[]' do
    expect { repository.sort_by_symbol }.to raise_error(ArgumentError, /Sort by columns with Col\[\]/)
  end

  it 'raises for limits that are not positive integers' do
    expect { repository.limit_by_float }.to raise_error(ArgumentError, /positive integer/)
  end

  it 'raises for two limits' do
    expect { repository.limit_twice }.to raise_error(ArgumentError, /one limit/)
  end

  it 'raises for invalid Col arguments' do
    expect { LowData::Col['views'] }.to raise_error(ArgumentError, /column names/)
    expect { LowData::Col[:views][2] }.to raise_error(ArgumentError, /range of integers/)
    expect { LowData::Col[:views][-1..] }.to raise_error(ArgumentError, /count from 0/)
    expect { LowData::Col[:views] + :title }.to raise_error(ArgumentError, /Add sort columns with Col\[\]/)
  end
end
