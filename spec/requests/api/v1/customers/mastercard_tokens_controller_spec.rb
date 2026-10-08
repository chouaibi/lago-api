# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::MastercardTokensController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "mastercard") }
  let(:mastercard_customer) { create(:mastercard_customer, customer:) }
  let(:external_id) { customer.external_id }
  let(:params) do
    {
      token: "9999000011112222",
      agreement_id: "agreement-1",
      last4: "2222",
      brand: "mastercard",
      expiration_month: 12,
      expiration_year: 2030,
      card_holder_name: "Jane Doe"
    }
  end

  describe "POST /api/v1/customers/:external_id/mastercard_token" do
    subject do
      post_with_token(organization, "/api/v1/customers/#{external_id}/mastercard_token", {mastercard_token: params})
    end

    before { mastercard_customer }

    include_examples "requires API permission", "payment_method", "write"

    it "stores the card token as the default payment method of the customer" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:customer][:lago_id]).to eq(customer.id)
      expect(mastercard_customer.reload).to have_attributes(token: "9999000011112222", agreement_id: "agreement-1")
      expect(customer.payment_methods.sole).to have_attributes(
        provider_method_id: "9999000011112222",
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
    end

    context "without token" do
      let(:params) { {token: "", agreement_id: "agreement-1"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(token: ["value_is_mandatory"])
      end
    end

    context "with unknown customer" do
      let(:external_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("customer")
      end
    end

    context "when the customer is not connected to mastercard" do
      let(:mastercard_customer) { nil }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("mastercard_customer")
      end
    end
  end
end
