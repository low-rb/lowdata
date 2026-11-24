# frozen_string_literal: true

require_relative '../lib/lowdata'
require_relative 'helpers/database'

class RequestStandInEvent < LowEvent
end

RSpec.describe LowData::DataEvent do
  let(:database) { SpecDatabase.connect }
  let(:pool) { Low::Events::EventPool.new }

  before do
    allow(Providers).to receive(:[]).and_call_original
    allow(Providers).to receive(:[]).with('low.event.pool').and_return(pool)
    LowData.database = database
  end

  it 'times each query under the event that ran it' do
    request = RequestStandInEvent.new(key: :request)
    request.trigger
    database.fetch('SELECT 1').all

    expect(request.children.map(&:class)).to eq([described_class])
    expect(request.children.first.milliseconds).to be >= 0
  end

  it 'only runs a query when nothing is happening to time it under' do
    expect([database.fetch('SELECT 1 AS one').first[:one], pool.event_trees.size]).to eq([1, 0])
  end
end
