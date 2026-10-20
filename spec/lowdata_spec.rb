# frozen_string_literal: true

require_relative '../lib/lowdata'

RSpec.describe LowData do
  describe '.table' do
    it 'names the table after the repository' do
      stub_const('BlogPostsData', Class.new(described_class))
      expect(BlogPostsData.table).to eq(:blog_posts)
    end
  end

  describe '.const_missing' do
    it 'resolves constants in a repository to snake case tables' do
      repository = Class.new(described_class)
      expect(repository.const_missing(:BlogPosts).table).to eq(:blog_posts)
    end

    it 'raises for Table when the repository has no table' do
      expect { Class.new(described_class).const_missing(:Table) }.to raise_error(LowData::ConfigError)
    end

    it 'does not resolve constants on LowData itself' do
      expect { LowData::Typo }.to raise_error(NameError)
    end
  end
end
