# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::Mastercard::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:membership) { create(:membership) }
  let(:mastercard_provider) { create(:mastercard_provider, organization: membership.organization, webhook_secret: nil) }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateMastercardPaymentProviderInput!) {
        updateMastercardPaymentProvider(input: $input) {
          id,
          region,
          testMode,
          webhookSecret
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates a mastercard provider" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {
        input: {
          id: mastercard_provider.id,
          region: "ap",
          testMode: true,
          webhookSecret: "GATEWAY_SECRET"
        }
      }
    )

    result_data = result["data"]["updateMastercardPaymentProvider"]

    expect(result_data["id"]).to eq(mastercard_provider.id)
    expect(result_data["region"]).to eq("ap")
    expect(result_data["testMode"]).to be(true)
    expect(result_data["webhookSecret"]).to eq("GATEWAY_SECRET")
    expect(mastercard_provider.reload.merchant_id).to be_present
  end
end
