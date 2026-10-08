# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Mastercard::HandleEventService do
  subject(:event_service) { described_class.new(organization:, event_json:) }

  let(:organization) { create(:organization) }
  let(:event_json) { {result: "SUCCESS", order: {id: "order-1"}, transaction: {id: "transaction-1", type: transaction_type}}.to_json }
  let(:transaction_type) { "PAYMENT" }

  before do
    allow(PaymentProviders::Mastercard::Webhooks::PaymentCompletedService).to receive(:call!)
    allow(PaymentProviders::Mastercard::Webhooks::RefundUpdatedService).to receive(:call!)
  end

  describe "#call" do
    %w[AUTHORIZATION PAYMENT CAPTURE].each do |type|
      context "with a #{type} transaction" do
        let(:transaction_type) { type }

        it "updates the payment" do
          expect(event_service.call).to be_success

          expect(PaymentProviders::Mastercard::Webhooks::PaymentCompletedService)
            .to have_received(:call!).with(organization_id: organization.id, event_json:)
        end
      end
    end

    context "with a REFUND transaction" do
      let(:transaction_type) { "REFUND" }

      it "updates the refund" do
        expect(event_service.call).to be_success

        expect(PaymentProviders::Mastercard::Webhooks::RefundUpdatedService)
          .to have_received(:call!).with(organization_id: organization.id, event_json:)
      end
    end

    context "with another transaction type" do
      let(:transaction_type) { "VOID_PAYMENT" }

      it "ignores the notification" do
        expect(event_service.call).to be_success

        expect(PaymentProviders::Mastercard::Webhooks::PaymentCompletedService).not_to have_received(:call!)
        expect(PaymentProviders::Mastercard::Webhooks::RefundUpdatedService).not_to have_received(:call!)
      end
    end

    context "when the processing fails" do
      before do
        allow(PaymentProviders::Mastercard::Webhooks::PaymentCompletedService).to receive(:call!).and_raise(StandardError, "boom")
        allow(Rails.logger).to receive(:error)
      end

      it "logs the error" do
        expect(event_service.call).to be_success

        expect(Rails.logger).to have_received(:error).with("Mastercard event processing error: boom")
      end
    end
  end
end
