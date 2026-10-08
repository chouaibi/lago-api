# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::Mastercard::StoreCustomerToken do
  let(:required_permission) { "payment_methods:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:, payment_provider: "mastercard") }
  let(:mastercard_customer) { create(:mastercard_customer, customer:) }
  let(:customer_id) { customer.id }

  let(:mutation) do
    <<-GQL
      mutation($input: StoreMastercardCustomerTokenInput!) {
        storeMastercardCustomerToken(input: $input) {
          id
        }
      }
    GQL
  end

  let(:input) do
    {
      customerId: customer_id,
      token: "9999000011112222",
      agreementId: "agreement-1",
      last4: "2222",
      brand: "mastercard",
      expirationMonth: 12,
      expirationYear: 2030,
      cardHolderName: "Jane Doe"
    }
  end

  before { mastercard_customer }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "payment_methods:create"

  it "stores the card token as the default payment method of the customer" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )

    expect(result["data"]["storeMastercardCustomerToken"]["id"]).to eq(customer.id)
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

  context "when the customer is not found" do
    let(:customer_id) { SecureRandom.uuid }

    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )

      expect_not_found(result)
    end
  end

  context "when the customer is not connected to mastercard" do
    let(:mastercard_customer) { nil }

    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )

      expect_not_found(result, details: {mastercardCustomer: ["not_found"]})
    end
  end
end
