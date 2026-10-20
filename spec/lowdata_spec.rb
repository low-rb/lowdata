# frozen_string_literal: true

require_relative '../lib/lowdata'

RSpec.describe LowData do
  describe '.const_missing' do
    it 'resolves constants in a repository to snake case tables' do
      repository = Class.new(described_class)
      expect(repository.const_missing(:BlogPosts).table).to eq(:blog_posts)
    end

    it 'does not resolve constants on LowData itself' do
      expect { LowData::Typo }.to raise_error(NameError)
    end
  end
end
