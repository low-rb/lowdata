# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'

class FactoryData < LowData
  self.table = :posts

  def retitle(id, title) = Posts(id:)[:title] = title
  def greet(name, punctuation: '!') = "Hello #{name}#{punctuation}"
  def yielded = yield
  def ready? = true
  def title=(value); end
  private def inline_secret = 'private' # rubocop:disable Style/AccessModifierDeclarations
  def later_secret = 'private'
  private :later_secret

  private

  def secret = 'private'
end

class ChildFactoryData < FactoryData
  def greet(name, punctuation: '!') = "Hi #{name}#{punctuation}"
  private def ready? = false # rubocop:disable Style/AccessModifierDeclarations
end

RSpec.describe 'Method Factory' do
  include SpecDatabase

  it 'calls the instance method of the same name' do
    expect(FactoryData.greet('Rudolph')).to eq('Hello Rudolph!')
  end

  it 'passes positional, keyword and block arguments' do
    expect(FactoryData.greet('Rudolph', punctuation: '?')).to eq('Hello Rudolph?')
    expect(FactoryData.yielded { 'from block' }).to eq('from block')
  end

  it 'defines predicate methods' do
    expect(FactoryData.ready?).to be(true)
  end

  it 'calls the subclass instance method from an inherited class method' do
    expect(ChildFactoryData.greet('Rudolph')).to eq('Hi Rudolph!')
  end

  it 'keeps existing class methods, warning that the instance method has none' do
    repository = nil
    expect { repository = Class.new(LowData) { def table = :instance_table }.tap { |data| data.table = :posts } }
      .to output(/#table has no class method, because .*\.table exists/).to_stderr

    expect(repository.table).to eq(:posts)
    expect(repository.new.table).to eq(:instance_table)
  end

  it 'does not define class methods for private methods or setters' do
    expect(FactoryData.respond_to?(:secret, true)).to be(false)
    expect(FactoryData.respond_to?(:title=)).to be(false)
  end

  it 'raises for methods made private after they are defined' do
    expect { FactoryData.inline_secret }.to raise_error(NoMethodError, /private method 'inline_secret'/)
    expect { FactoryData.later_secret }.to raise_error(NoMethodError, /private method 'later_secret'/)
  end

  it 'raises when a subclass makes an inherited method private' do
    expect { ChildFactoryData.ready? }.to raise_error(NoMethodError, /private method 'ready\?'/)
  end

  context 'with a database' do
    let(:database) { SpecDatabase.connect }

    before do
      database.create_table(:users) { primary_key :id }
      database.create_table(:posts) do
        primary_key :id
        String :title
      end
      database[:posts].insert(title: 'Old')
      LowData.database = database
    end

    after { LowData.database = nil }

    it 'writes through the class method' do
      FactoryData.retitle(1, 'New')

      expect(database[:posts].select_map(:title)).to eq(['New'])
    end
  end
end
