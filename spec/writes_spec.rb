# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'

class WritesData < LowData
  self.table = :posts

  def create(post) = Posts << post
  def create_returning(post) = Posts[:id, :title] << post
  def create_renamed(post) = Posts[:id, headline: :title] << post
  def create_own(post) = Table << post
  def create_filtered(post) = Posts(title: 'Hello') << post
  def create_filtered_columns(post) = Posts(title: 'Hello')[:id] << post
  def create_nested(post) = Posts[:title, Users[:username]] << post
  def create_joined(post) = (Posts[:title] & Users[:username]) << post
  def create_sorted(post) = (Posts[:title] ^ Col[:id]) << post
  def create_missing_column(post) = Posts[:slug] << post
  def append_expression = Posts << Users[:username]

  def tag(name, row = {}) = Tags(name:) <= row
  def tag_returning(name, row = {}) = Tags(name:)[:id, :name] <= row
  def tag_by_key(row) = Tags <= row
  def upsert_post(row) = Posts <= row
  def upsert_titled(title, row) = Posts(title:) <= row
  def tag_by_unindexed(row) = Tags(id: 1, name: 'ruby') <= row
  def tag_range(row) = Tags(id: 1..) <= row
  def tag_block(row) = Tags { id > 1 } <= row
  def compare = Posts[:id] <= Users[:id]

  def retitle(id, title) = Posts(id:)[:title] = title
  def retitle_many(id, values) = Posts(id:)[:title, :views] = values
  def retitle_hash(id, values) = Posts(id:)[] = values
  def retitle_unviewed = Posts { views < 100 }[:title] = 'Quiet'
  def retitle_postless = Users(~Posts)[:username] = 'lurker'
  def retitle_all = Posts[:title] = 'All'
  def retitle_all_hash = Posts[] = { title: 'All' }
  def retitle_mismatched(id) = Posts(id:)[:title, :views] = ['One']
  def retitle_foreign_key = Posts(:user_id)[:title] = 'Linked'

  def remove(id) = Posts(id:).delete
  def remove_viewed = Posts(views: 100..).delete
  def remove_all = Posts.delete
  def remove_columns(id) = Posts(id:)[:title].delete
  def remove_negated = (~Posts).delete
end

RSpec.describe 'Writing with <<, <=, []= and delete' do
  subject(:repository) { WritesData.new }

  include_context 'with a database'

  before { database.add_index(:tags, :name, unique: true) }

  let(:post) { { user_id: 1, title: 'New', views: 5 } }

  describe 'insert with <<' do
    it 'inserts a row and returns its primary key' do
      expect(repository.create(post)).to eq({ id: 4 })
      expect(database[:posts][id: 4]).to include(title: 'New', views: 5)
    end

    it 'returns the columns in square brackets' do
      expect(repository.create_returning(post)).to eq({ id: 4, title: 'New' })
    end

    it 'returns renamed columns' do
      expect(repository.create_renamed(post)).to eq({ id: 4, headline: 'New' })
    end

    it "inserts into the repository's table with Table" do
      expect(repository.create_own(post)).to eq({ id: 4 })
    end

    it 'inserts an array of rows and returns an array' do
      rows = [{ title: 'One' }, { title: 'Two' }]

      expect(repository.create(rows)).to eq([{ id: 4 }, { id: 5 }])
      expect(database[:posts].where(id: [4, 5]).select_map(:title)).to eq(%w[One Two])
    end

    it 'inserts nothing for an empty array' do
      expect(repository.create([])).to eq([])
      expect(database[:posts].count).to eq(3)
    end

    it 'inserts every row or none' do
      expect { repository.create([{ title: 'One' }, { slug: 'unknown' }]) }.to raise_error(Sequel::DatabaseError)
      expect(database[:posts].count).to eq(3)
    end

    it 'raises for round brackets, which choose existing rows' do
      expect { repository.create_filtered(post) }.to raise_error(ArgumentError, /upsert with <=/)
      expect { repository.create_filtered_columns(post) }.to raise_error(ArgumentError, /upsert with <=/)
      expect(database[:posts].count).to eq(3)
    end

    it 'raises for anything but a hash or an array of hashes' do
      expect { repository.create('New') }.to raise_error(ArgumentError, /<< takes a hash or an array of hashes/)
      expect { repository.create([post, 'New']) }.to raise_error(ArgumentError, /<< takes a hash/)
    end

    it 'raises for a data expression' do
      expect { repository.append_expression }.to raise_error(ArgumentError, /<< inserts rows/)
    end

    it 'raises for nested, joined or sorted tables' do
      expect { repository.create_nested(post) }.to raise_error(ArgumentError, /<< writes to one table/)
      expect { repository.create_joined(post) }.to raise_error(ArgumentError, /<< writes to one table/)
      expect { repository.create_sorted(post) }.to raise_error(ArgumentError, /<< writes to one table/)
    end

    it 'raises before inserting for a column the table lacks' do
      expect { repository.create_missing_column(post) }.to raise_error(ArgumentError, 'posts has no slug column to return')
      expect(database[:posts].count).to eq(3)
    end
  end

  describe 'upsert with <=' do
    it 'inserts a row when none matches' do
      expect(repository.tag('ruby')).to eq({ id: 1 })
      expect(database[:tags].all).to eq([{ id: 1, name: 'ruby' }])
    end

    it 'updates the matching row rather than inserting another' do
      database[:tags].insert(id: 7, name: 'ruby')

      expect(repository.tag('ruby')).to eq({ id: 7 })
      expect(database[:tags].count).to eq(1)
    end

    it 'writes the round brackets and the row together' do
      database.add_index(:posts, :title, unique: true)

      expect(repository.upsert_titled('Fresh', { views: 7 })).to eq({ id: 4 })
      expect(database[:posts][id: 4]).to include(title: 'Fresh', views: 7)
    end

    it 'matches on the primary key without round brackets' do
      expect(repository.upsert_post({ id: 1, title: 'Changed' })).to eq({ id: 1 })
      expect(database[:posts][id: 1]).to include(title: 'Changed', views: 10)
      expect(database[:posts].count).to eq(3)
    end

    it 'returns the columns in square brackets' do
      expect(repository.tag_returning('ruby')).to eq({ id: 1, name: 'ruby' })
    end

    it 'upserts an array of rows' do
      expect(repository.upsert_post([{ id: 1, title: 'One' }, { id: 9, title: 'Nine' }])).to eq([{ id: 1 }, { id: 9 }])
      expect(database[:posts].where(id: [1, 9]).order(:id).select_map(:title)).to eq(%w[One Nine])
    end

    it 'raises without round brackets when the row has no primary key' do
      expect { repository.tag_by_key({ name: 'ruby' }) }.to raise_error(ArgumentError, /the row needs id/)
    end

    it 'raises for filters that match more than plain values' do
      expect { repository.tag_range({ name: 'ruby' }) }.to raise_error(ArgumentError, /matches one row by plain values/)
      expect { repository.tag_block({ name: 'ruby' }) }.to raise_error(ArgumentError, /matches one row by plain values/)
    end

    context 'on MySQL, which matches any unique key' do
      before { skip 'MySQL only' unless database.database_type == :mysql }

      it 'raises when the row sets another unique key, which could match a different row' do
        expect { repository.tag_by_key({ id: 7, name: 'sql' }) }.to raise_error(LowData::Error, /the row also sets name/)
      end

      it "raises when the round brackets aren't a unique key" do
        expect { repository.tag_by_unindexed({}) }.to raise_error(LowData::Error, /id, name isn't one of tags's/)
      end
    end

    it "raises for a data expression, so it can't be mistaken for a comparison or a join" do
      expect { repository.compare }.to raise_error(ArgumentError, /<= upserts rows/)
    end
  end

  describe 'update with []=' do
    it 'updates a column of the rows in round brackets and returns the assigned value' do
      expect(repository.retitle(1, 'Changed')).to eq('Changed')
      expect(database[:posts].order(:id).select_map(:title)).to eq(%w[Changed World Orphan])
    end

    it 'updates several columns from an array' do
      repository.retitle_many(1, ['Changed', 99])

      expect(database[:posts][id: 1]).to include(title: 'Changed', views: 99)
    end

    it 'updates the columns in a hash with empty brackets' do
      repository.retitle_hash(1, { title: 'Changed', views: 99 })

      expect(database[:posts][id: 1]).to include(title: 'Changed', views: 99)
    end

    it 'chooses rows with a block' do
      repository.retitle_unviewed

      expect(database[:posts].order(:id).select_map(:title)).to eq(%w[Quiet World Orphan])
    end

    it 'chooses rows by related tables' do
      repository.retitle_postless

      expect(database[:users].order(:id).select_map(:username)).to eq(%w[alice bob lurker])
    end

    it 'raises without round brackets, rather than changing every row' do
      expect { repository.retitle_all }
        .to raise_error(ArgumentError, 'Choose the posts to update with round brackets, e.g. Posts(id: 1)[:title] = "All"')
      expect { repository.retitle_all_hash }.to raise_error(ArgumentError, /Choose the posts to update/)
      expect(database[:posts].select_map(:title)).not_to include('All')
    end

    it 'raises when the values and columns differ in number' do
      expect { repository.retitle_mismatched(1) }.to raise_error(ArgumentError, /2 columns take 2 values/)
    end

    it 'raises for a hash assigned to one column, rather than writing it as a condition' do
      expect { repository.retitle(1, { title: 'Changed', views: 99 }) }
        .to raise_error(ArgumentError, /One column takes one value, not a hash/)
      expect(database[:posts][id: 1]).to include(title: 'Hello', views: 10)
    end

    it 'raises for empty brackets without a hash' do
      expect { repository.retitle_hash(1, 'Changed') }.to raise_error(ArgumentError, /Empty brackets take a hash/)
    end

    it 'raises for a foreign key in round brackets, which chooses no rows' do
      expect { repository.retitle_foreign_key }.to raise_error(ArgumentError, /names a foreign key/)
    end
  end

  describe 'delete' do
    before do
      database[:comments].delete
      database[:likes].delete
    end

    it 'deletes the rows in round brackets and returns how many' do
      expect(repository.remove(1)).to eq(1)
      expect(database[:posts].select_map(:id)).to contain_exactly(2, 3)
    end

    it 'deletes by any filter' do
      expect(repository.remove_viewed).to eq(1)
      expect(database[:posts].select_map(:id)).to contain_exactly(1, 3)
    end

    it 'raises without round brackets, rather than deleting every row' do
      expect { repository.remove_all }
        .to raise_error(ArgumentError, 'Choose the posts to delete with round brackets, e.g. Posts(id: 1).delete')
      expect(database[:posts].count).to eq(3)
    end

    it 'raises after square brackets, which choose columns' do
      expect { repository.remove_columns(1) }.to raise_error(ArgumentError, /a delete removes whole rows/)
    end

    it 'raises for a negated table' do
      expect { repository.remove_negated }.to raise_error(ArgumentError, /~Posts filters by related rows/)
    end
  end
end
