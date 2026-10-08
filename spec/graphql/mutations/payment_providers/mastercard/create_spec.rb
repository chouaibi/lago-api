# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::Mastercard::Create do
  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: AddMastercardPaymentProviderInput!) {
        addMastercardPaymentProvider(input: $input) {
          id,
          code,
          name,
          merchantId,
          apiPassword,
          region,
          testMode,
          webhookSecret
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  it "creates a mastercard provider" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      # `view` is necessary to retrieve the created record in the response
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {
        input: {
          code: "mastercard_1",
          name: "Mastercard",
          merchantId: "MERCHANT_123456",
          apiPassword: "api_password_123456",
          region: "eu",
          testMode: true,
          webhookSecret: "GATEWAY_SECRET"
        }
      }
    )

    result_data = result["data"]["addMastercardPaymentProvider"]

    expect(result_data["id"]).to be_present
    expect(result_data["code"]).to eq("mastercard_1")
    expect(result_data["name"]).to eq("Mastercard")
    expect(result_data["merchantId"]).to eq("••••••••…456")
    expect(result_data["apiPassword"]).to eq("••••••••…456")
    expect(result_data["region"]).to eq("eu")
    expect(result_data["testMode"]).to be(true)
    expect(result_data["webhookSecret"]).to eq("GATEWAY_SECRET")
  end
end
