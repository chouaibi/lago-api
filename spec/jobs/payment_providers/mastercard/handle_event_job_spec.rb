# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Mastercard::HandleEventJob do
  let(:organization) { create(:organization) }
  let(:event_json) { {transaction: {id: "transaction-1", type: "PAYMENT"}}.to_json }

  before { allow(PaymentProviders::Mastercard::HandleEventService).to receive(:call!) }

  it "calls the HandleEventService" do
    described_class.perform_now(organization:, event: event_json)

    expect(PaymentProviders::Mastercard::HandleEventService)
      .to have_received(:call!).with(organization:, event_json:)
  end

  describe "queue" do
    context "when SIDEKIQ_PAYMENTS is true" do
      before { ENV["SIDEKIQ_PAYMENTS"] = "true" }
      after { ENV.delete("SIDEKIQ_PAYMENTS") }

      it "uses the payments queue" do
        expect(described_class.new.queue_name).to eq("payments")
      end
    end

    context "without SIDEKIQ_PAYMENTS" do
      it "uses the providers queue" do
        expect(described_class.new.queue_name).to eq("providers")
      end
    end
  end
end
