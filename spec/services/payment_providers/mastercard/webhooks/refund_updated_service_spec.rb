# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Mastercard::Webhooks::RefundUpdatedService do
  subject(:refund_updated_service) { described_class.new(organization_id: organization.id, event_json:) }

  let(:organization) { create(:organization) }
  let(:event_json) { {result:, order: {id: "order-1"}, transaction: {id: "refund-transaction-1", type: "REFUND"}}.to_json }
  let(:result) { "SUCCESS" }
  let(:refund_service) { instance_double(CreditNotes::Refunds::MastercardService) }

  before do
    allow(CreditNotes::Refunds::MastercardService).to receive(:new).and_return(refund_service)
    allow(refund_service).to receive(:update_status).and_return(CreditNotes::Refunds::MastercardService::Result.new)
  end

  describe "#call" do
    {"SUCCESS" => :succeeded, "FAILURE" => :failed, "PENDING" => :pending}.each do |gateway_result, status|
      context "when the refund result is #{gateway_result}" do
        let(:result) { gateway_result }

        it "updates the refund status" do
          expect(refund_updated_service.call).to be_success

          expect(refund_service).to have_received(:update_status).with(
            provider_refund_id: "refund-transaction-1",
            status:,
            metadata: {lago_invoice_id: "order-1"}
          )
        end
      end
    end

    context "with an unknown result" do
      let(:result) { "UNKNOWN" }

      it "ignores the notification" do
        expect(refund_updated_service.call).to be_success

        expect(refund_service).not_to have_received(:update_status)
      end
    end
  end
end
