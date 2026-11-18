# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'

# Queries shared by repositories, written in a module with their tables as constants.
module SharedQueries
  include LowData::Queries

  def titled = Table()[:title, :username]
  def most_viewed = Posts[:title] ^ -Col[:views] * 1
end

class SharedPostsData < LowData
  self.table = :posts

  include SharedQueries
end

RSpec.describe LowData::Queries do
  include_context 'with a database'

  it "finds a module's tables as a repository does" do
    expect(SharedPostsData.new.most_viewed.to_a).to eq([{ title: 'World' }])
  end

  it 'calls Table(...) on the repository that includes the module' do
    expect(SharedPostsData.new.titled.to_a.first).to eq({ title: 'Hello', username: 'alice' })
  end

  it "gives the repository a class method for each of the module's queries" do
    expect(SharedPostsData.most_viewed.to_a).to eq([{ title: 'World' }])
  end

  it 'explains that Table is written as a method call in the module' do
    expect { SharedQueries::Table }.to raise_error(NameError, /Write Table\(\.\.\.\)/)
  end
end
