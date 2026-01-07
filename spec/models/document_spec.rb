require 'spec_helper'

RSpec.describe 'SourceDocument Model' do
  include DatabaseHelpers

  before(:all) do
    @db = SmartRAG.db
  end

  describe 'CRUD operations' do
    it 'creates a new document' do
      doc = FactoryBot.build(:source_document)
      expect { doc.save }.to change { @db[:source_documents].count }.by(1)
    end

    it 'reads a document' do
      doc = FactoryBot.create(:source_document)
      found = @db[:source_documents].where(id: doc.id).first
      expect(found[:title]).to eq(doc.title)
    end

    it 'updates a document' do
      doc = FactoryBot.create(:source_document)
      new_title = 'Updated Title'
      @db[:source_documents].where(id: doc.id).update(title: new_title)
      updated = @db[:source_documents].where(id: doc.id).first
      expect(updated[:title]).to eq(new_title)
    end

    it 'deletes a document' do
      doc = FactoryBot.create(:source_document)
      expect { @db[:source_documents].where(id: doc.id).delete }.to change { @db[:source_documents].count }.by(-1)
    end
  end

  describe 'validations' do
    it 'requires a title' do
      doc = FactoryBot.build(:source_document, title: nil)
      expect { doc.save }.to raise_error(Sequel::ValidationFailed, /title is not present/)
    end

    it 'validates download_state range' do
      expect {
        FactoryBot.create(:source_document, download_state: 3)
      }.to raise_error(Sequel::ValidationFailed, /download_state is not in range or set/)
    end
  end

  describe 'associations' do
    it 'has many sections' do
      doc = FactoryBot.create(:source_document)
      3.times { FactoryBot.create(:source_section, document: doc) }

      section_count = @db[:source_sections].where(document_id: doc.id).count
      expect(section_count).to eq(3)
    end

    it 'cascades delete to sections' do
      doc = FactoryBot.create(:source_document)
      sections = 3.times.map { FactoryBot.create(:source_section, document: doc) }

      expect {
        @db[:source_documents].where(id: doc.id).delete
      }.to change { @db[:source_sections].count }.by(-3)
    end
  end

  describe 'scopes/filters' do
    before do
      @docs = [
        FactoryBot.create(:source_document, download_state: 0),
        FactoryBot.create(:source_document, download_state: 1),
        FactoryBot.create(:source_document, download_state: 2),
      ]
    end

    it 'filters by download_state' do
      pending_docs = @db[:source_documents].where(download_state: 0).all
      expect(pending_docs.count).to eq(1)

      completed_docs = @db[:source_documents].where(download_state: 1).all
      expect(completed_docs.count).to eq(1)
    end

    it 'orders by publication_date' do
      old_date_doc = FactoryBot.create(:source_document, publication_date: Date.today - 30)
      new_date_doc = FactoryBot.create(:source_document, publication_date: Date.today)

      ordered = @db[:source_documents]
        .order(Sequel.desc(:publication_date))
        .limit(2)
        .all

      expect(ordered.first[:id]).to eq(new_date_doc.id)
    end
  end
end
