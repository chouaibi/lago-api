# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::MastercardProvider do
  subject(:mastercard_provider) { build(:mastercard_provider, merchant_id:, api_password:, region:, test_mode:) }

  let(:merchant_id) { "MERCHANT1" }
  let(:api_password) { "secret" }
  let(:region) { "eu" }
  let(:test_mode) { false }

  describe "validations" do
    it { is_expected.to validate_presence_of(:merchant_id) }
    it { is_expected.to validate_presence_of(:api_password) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:region) }
    it { is_expected.to validate_inclusion_of(:region).in_array(%w[ap eu na]) }

    it "validates uniqueness of the code" do
      expect(mastercard_provider).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe "#payment_type" do
    it { expect(mastercard_provider.payment_type).to eq("mastercard") }
  end

  describe "#webhook_secret" do
    subject(:mastercard_provider) { create(:mastercard_provider, webhook_secret:) }

    context "when the gateway notification secret is provided" do
      let(:webhook_secret) { "ABCDEF0123456789" }

      it "stores it as provided" do
        expect(mastercard_provider.reload.webhook_secret).to eq("ABCDEF0123456789")
      end
    end

    context "without notification secret" do
      let(:webhook_secret) { nil }

      it "does not generate one" do
        expect(mastercard_provider.reload.webhook_secret).to be_nil
      end
    end
  end

  describe "#test_mode?" do
    it { expect(mastercard_provider.test_mode?).to be(false) }

    context "when test mode is enabled" do
      let(:test_mode) { true }

      it { expect(mastercard_provider.test_mode?).to be(true) }
    end

    context "without test mode setting" do
      subject(:mastercard_provider) { described_class.new }

      it { expect(mastercard_provider.test_mode?).to be(false) }
    end
  end

  describe "#api_url" do
    it "targets the merchant on the regional gateway" do
      expect(mastercard_provider.api_url).to eq("https://eu-gateway.mastercard.com/api/rest/version/100/merchant/MERCHANT1")
    end

    context "when test mode is enabled" do
      let(:test_mode) { true }
      let(:region) { "ap" }

      it "targets the merchant test profile on the same regional gateway" do
        expect(mastercard_provider.api_url).to eq("https://ap-gateway.mastercard.com/api/rest/version/100/merchant/TESTMERCHANT1")
      end
    end
  end

  describe "#api_headers" do
    it "authenticates as the merchant" do
      expect(mastercard_provider.api_headers).to eq(
        "Authorization" => "Basic #{Base64.strict_encode64("merchant.MERCHANT1:secret")}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      )
    end

    context "when test mode is enabled" do
      let(:test_mode) { true }

      it "authenticates as the merchant test profile" do
        expect(mastercard_provider.api_headers["Authorization"])
          .to eq("Basic #{Base64.strict_encode64("merchant.TESTMERCHANT1:secret")}")
      end
    end
  end

  describe "#determine_payment_status" do
    it "maps the gateway statuses" do
      expect(mastercard_provider.determine_payment_status("CAPTURED")).to eq(:succeeded)
      expect(mastercard_provider.determine_payment_status("PENDING")).to eq(:processing)
      expect(mastercard_provider.determine_payment_status("DECLINED")).to eq(:failed)
    end
  end
end
