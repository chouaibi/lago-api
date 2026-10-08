# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Mastercard::Webhooks::PaymentCompletedService do
  subject(:payment_completed_service) { described_class.new(organization_id: organization.id, event_json:) }

  let(:organization) { create(:organization) }
  let(:mastercard_provider) { create(:mastercard_provider, organization:) }
  let(:invoice) { create(:invoice, organization:) }
  let(:event_json) { {result: "SUCCESS", order: {id: invoice.id}, transaction: {id: "transaction-1", type: "PAYMENT"}}.to_json }
  let(:order_url) { "#{mastercard_provider.api_url}/order/#{invoice.id}" }

  before do
    stub_request(:get, order_url).to_return(status: 200, body: {order: {id: invoice.id, status: "CAPTURED"}}.to_json)
    allow(Invoices::Payments::MastercardService).to receive(:call!)
  end

  describe "#call" do
    it "updates the payment of the invoice with the order status read back from the gateway" do
      expect(payment_completed_service.call).to be_success

      expect(WebMock).to have_requested(:get, order_url).with(headers: mastercard_provider.api_headers)
      expect(Invoices::Payments::MastercardService).to have_received(:call!).with(
        :update_payment_status,
        organization_id: organization.id,
        provider_payment_id: invoice.id,
        status: "CAPTURED"
      )
    end

    context "when the gateway cannot be reached" do
      before { stub_request(:get, order_url).to_return(status: 500, body: "") }

      it "does not update the payment" do
        expect(payment_completed_service.call).to be_success

        expect(Invoices::Payments::MastercardService).not_to have_received(:call!)
      end
    end
  end
end
