# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'

class OperandsData < LowData
  self.table = :users

  def users = Users[:username]
  def posts = Posts[:title]
end

RSpec.describe 'Operators on data expressions' do
  subject(:repository) { OperandsData.new }

  include_context 'with a database'

  let(:users) { repository.users }
  let(:posts) { repository.posts }

  it 'leaves both operands unchanged, so a named expression can be reused' do
    nested = users + posts
    joined = users & posts

    expect(users.sql).to eq('SELECT `users`.`username` FROM `users`')
    expect(posts.sql).to eq('SELECT `posts`.`title` FROM `posts`')
    expect(nested.to_a).to include({ username: 'alice', posts: [{ title: 'Hello' }] })
    expect(joined.to_a).to include({ username: 'alice', title: 'Hello' })
  end

  it 'leaves the expression unchanged when sorting, limiting and paging' do
    sorted = posts ^ -LowData::Col[:views]
    limited = posts * 1
    paged = posts / 2

    expect(posts.sql).to eq('SELECT `posts`.`title` FROM `posts`')
    expect(sorted.sql).to end_with('ORDER BY `posts`.`views` DESC')
    expect(limited.sql).to end_with('LIMIT 1')
    expect(paged[0].sql).to end_with('LIMIT 2')
  end

  it 'returns a new expression for each operator in a chain' do
    with_posts = users + posts
    with_more = with_posts + [repository.posts]

    expect(with_posts).not_to equal(with_more)
    expect(with_posts.to_a).to include({ username: 'alice', posts: [{ title: 'Hello' }] })
  end
end
