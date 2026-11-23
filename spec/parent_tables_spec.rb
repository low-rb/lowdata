# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'
require_relative 'fixtures/parent_tables_data'

RSpec.describe 'Parent tables' do
  subject(:repository) { ParentTablesData.new }

  include_context 'with a database'

  it "nests the rows that point at a table's parent under it" do
    expect(repository.notes_with_photos.to_a).to contain_exactly(
      { title: 'Rye', photos: [{ path: 'loaf.jpg' }, { path: 'crumb.jpg' }] },
      { title: 'Spelt', photos: [] }
    )
  end

  it 'nests a table under the rows that point at its parent' do
    expect(repository.photos_with_notes.to_a).to eq(
      [{ path: 'loaf.jpg', notes: { title: 'Rye' } }, { path: 'crumb.jpg', notes: { title: 'Rye' } }]
    )
  end

  it "joins the rows that point at a table's parent" do
    expect(repository.notes_joined.to_a).to eq([{ title: 'Rye', path: 'crumb.jpg' }, { title: 'Rye', path: 'loaf.jpg' }])
  end

  it 'still nests the parent itself under its child' do
    expect(repository.notes_with_kind.to_a).to include({ title: 'Rye', content: { kind: 'notes' } })
  end
end
