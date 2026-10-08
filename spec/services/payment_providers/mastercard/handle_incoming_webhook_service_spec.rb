# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Mastercard::HandleIncomingWebhookService do
  subject(:webhook_service) { described_class.new(organization_id: organization.id, body:, secret:, code:) }

  let(:organization) { create(:organization) }
  let(:mastercard_provider) { create(:mastercard_provider, organization:, webhook_secret:) }
  let(:webhook_secret) { "5DCBD6F1D0E1A5E8D3E2A4B1C0F9E8D7" }
  let(:code) { mastercard_provider.code }
  let(:secret) { webhook_secret }
  let(:body) { {result: "SUCCESS", order: {id: "order-1"}, transaction: {id: "transaction-1", type: "PAYMENT"}}.to_json }

  describe "#call" do
    it "enqueues the event processing" do
      expect { webhook_service.call }
        .to have_enqueued_job(PaymentProviders::Mastercard::HandleEventJob).with(organization:, event: body)
    end

    it "returns the event" do
      result = webhook_service.call

      expect(result).to be_success
      expect(result.event).to eq(body)
    end

    context "when the notification secret does not match" do
      let(:secret) { "wrong" }

      it "returns a webhook error" do
        result = webhook_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("webhook_error")
        expect(result.error.error_message).to eq("Invalid webhook secret")
      end

      it "does not enqueue the event processing" do
        expect { webhook_service.call }.not_to have_enqueued_job(PaymentProviders::Mastercard::HandleEventJob)
      end
    end

    context "without notification secret header" do
      let(:secret) { nil }

      it "returns a webhook error" do
        result = webhook_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("webhook_error")
      end
    end

    context "when the provider has no notification secret" do
      let(:webhook_secret) { nil }
      let(:secret) { "" }

      it "returns a webhook error" do
        result = webhook_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("webhook_error")
        expect(result.error.error_message).to eq("Webhook secret is missing")
      end
    end

    context "when the payment provider is not found" do
      let(:code) { "unknown" }

      before { mastercard_provider }

      it "returns a failure" do
        result = webhook_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("payment_provider_not_found")
      end
    end
  end
end
