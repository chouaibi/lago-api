# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Mastercard::Customers::StoreTokenService do
  subject(:store_token_service) do
    described_class.new(mastercard_customer:, token:, agreement_id:, card_details:)
  end

  let(:customer) { create(:customer, payment_provider: "mastercard") }
  let(:mastercard_customer) { create(:mastercard_customer, customer:) }
  let(:token) { "9999000011112222" }
  let(:agreement_id) { "agreement-1" }
  let(:card_details) do
    {last4: "2222", brand: "mastercard", expiration_month: 12, expiration_year: 2030, card_holder_name: "Jane Doe"}
  end

  describe "#call" do
    it "stores the token as the default payment method of the customer" do
      result = store_token_service.call

      expect(result).to be_success
      expect(result.mastercard_customer).to eq(mastercard_customer)
      expect(result.payment_method).to have_attributes(
        customer:,
        organization_id: customer.organization_id,
        payment_provider_customer: mastercard_customer,
        payment_provider_id: mastercard_customer.payment_provider_id,
        provider_method_id: token,
        is_default: true,
        details: {
          "type" => "card",
          "last4" => "2222",
          "brand" => "mastercard",
          "expiration_month" => 12,
          "expiration_year" => 2030,
          "card_holder_name" => "Jane Doe"
        }
      )
      expect(mastercard_customer.reload.agreement_id).to eq("agreement-1")
      expect(mastercard_customer.token).to eq(token)
    end

    context "when the token is already stored" do
      let(:mastercard_customer) { create(:mastercard_customer, customer:, token:, agreement_id: "agreement-0") }

      it "refreshes the existing payment method and the agreement" do
        existing_payment_method = mastercard_customer.payment_methods.sole

        result = store_token_service.call

        expect(result.payment_method.id).to eq(existing_payment_method.id)
        expect(result.payment_method.details).to include("last4" => "2222", "card_holder_name" => "Jane Doe")
        expect(mastercard_customer.reload.agreement_id).to eq("agreement-1")
      end
    end

    context "when another card is the default payment method" do
      let(:mastercard_customer) { create(:mastercard_customer, customer:, token: "1111000011110000") }

      it "makes the new card the default one" do
        result = store_token_service.call

        expect(result.payment_method.is_default).to be(true)
        expect(customer.payment_methods.where(is_default: true).sole).to eq(result.payment_method)
        expect(mastercard_customer.reload.token).to eq(token)
      end
    end

    context "without agreement id" do
      let(:agreement_id) { nil }
      let(:mastercard_customer) { create(:mastercard_customer, customer:, agreement_id: "agreement-0") }

      it "keeps the stored agreement" do
        store_token_service.call

        expect(mastercard_customer.reload.agreement_id).to eq("agreement-0")
      end
    end

    context "without card details" do
      let(:card_details) { {} }

      it "stores the token without details" do
        result = store_token_service.call

        expect(result).to be_success
        expect(result.payment_method.details).to eq({})
      end
    end

    context "without token" do
      let(:token) { "" }

      it "returns a validation failure" do
        result = store_token_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(token: ["value_is_mandatory"])
      end
    end

    context "without mastercard customer" do
      let(:mastercard_customer) { nil }

      it "returns a not found failure" do
        result = store_token_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("mastercard_customer_not_found")
      end
    end
  end
end
