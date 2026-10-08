# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::MastercardService do
  let(:mastercard_customer) { create(:mastercard_customer) }

  describe ".call(:create)" do
    it "returns the mastercard customer" do
      result = described_class.call(:create, mastercard_customer)

      expect(result).to be_success
      expect(result.mastercard_customer).to eq(mastercard_customer)
    end
  end

  describe ".call(:update)" do
    it "succeeds without calling the gateway" do
      expect(described_class.call(:update, mastercard_customer)).to be_success
    end
  end

  describe ".call(:generate_checkout_url)" do
    it "is not supported" do
      result = described_class.call(:generate_checkout_url, mastercard_customer)

      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      expect(result.error.code).to eq("feature_not_supported")
    end
  end
end
