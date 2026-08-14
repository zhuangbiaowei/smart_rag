# frozen_string_literal: true

require 'unit_spec_helper'
require 'smart_rag/core/media_job_queue'

RSpec.describe SmartRAG::Core::MediaJobQueue do
  it 'fails clearly when the migration has not been run' do
    db = double('db', table_exists?: false)
    queue = described_class.new(db: db, handler: ->(*) {})

    expect { queue.enqueue(operation: :add_media, source: '/tmp/a') }
      .to raise_error(RuntimeError, /run database migrations/)
  end

  it 'serializes nested symbols and drops extractor objects' do
    dataset = double('dataset')
    db = double('db', table_exists?: true)
    allow(db).to receive(:transaction).with(savepoint: true).and_yield
    allow(db).to receive(:[]).with(:media_jobs).and_return(dataset)
    allow(dataset).to receive(:insert).and_return(9)
    allow(dataset).to receive(:where).with(id: 9).and_return(dataset)
    allow(dataset).to receive(:first).and_return(
      id: 9, options: '{"metadata":{"state":"ready"}}', result: nil
    )
    queue = described_class.new(db: db, handler: ->(*) {})

    result = queue.enqueue(operation: :add_media, source: '/tmp/a',
                           options: { metadata: { state: :ready }, image_describer: ->(_) {} })
    expect(result[:options]).to eq('metadata' => { 'state' => 'ready' })
    expect(dataset).to have_received(:insert) do |attributes|
      expect(JSON.parse(attributes[:options])).to eq('metadata' => { 'state' => 'ready' })
    end
  end
end
