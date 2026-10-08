# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::MastercardCustomer do
  subject(:mastercard_customer) { build(:mastercard_customer) }

  describe "#require_provider_payment_id?" do
    it { expect(mastercard_customer.require_provider_payment_id?).to be(false) }
  end

  describe "#agreement_id" do
    subject(:mastercard_customer) { build(:mastercard_customer, agreement_id: "agreement-1") }

    it "is stored in the settings" do
      expect(mastercard_customer.agreement_id).to eq("agreement-1")
      expect(mastercard_customer.settings).to eq("agreement_id" => "agreement-1")
    end
  end

  describe "#token" do
    subject(:mastercard_customer) { create(:mastercard_customer, token:) }

    let(:token) { "9999000011112222" }

    it "returns the token of the default payment method" do
      expect(mastercard_customer.token).to eq("9999000011112222")
    end

    context "without stored token" do
      let(:token) { nil }

      it { expect(mastercard_customer.token).to be_nil }
    end
  end
end
