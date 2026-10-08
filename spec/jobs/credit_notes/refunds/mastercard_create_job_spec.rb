# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::Refunds::MastercardCreateJob do
  let(:credit_note) { create(:credit_note) }
  let(:refund_service) { instance_double(CreditNotes::Refunds::MastercardService) }

  before do
    allow(CreditNotes::Refunds::MastercardService).to receive(:new).with(credit_note).and_return(refund_service)
    allow(refund_service).to receive(:create).and_return(CreditNotes::Refunds::MastercardService::Result.new)
  end

  it "delegates to the mastercard refund service" do
    described_class.perform_now(credit_note)

    expect(refund_service).to have_received(:create)
  end
end
