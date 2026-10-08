# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::MastercardService do
  subject(:mastercard_service) { described_class.new }

  include_context "with mocked security logger"

  let(:organization) { create(:organization) }
  let(:code) { "mastercard_1" }
  let(:args) do
    {
      organization:,
      code:,
      name: "Mastercard",
      merchant_id: "MERCHANT1",
      api_password: "secret",
      region: "eu",
      test_mode: true,
      webhook_secret: "GATEWAY_SECRET"
    }
  end

  describe "#create_or_update" do
    it "creates a mastercard provider" do
      result = mastercard_service.create_or_update(**args)

      expect(result).to be_success
      expect(result.mastercard_provider).to be_a(PaymentProviders::MastercardProvider)
      expect(result.mastercard_provider).to have_attributes(
        organization_id: organization.id,
        code:,
        name: "Mastercard",
        merchant_id: "MERCHANT1",
        api_password: "secret",
        region: "eu",
        test_mode?: true,
        webhook_secret: "GATEWAY_SECRET"
      )
    end

    it_behaves_like "produces a security log", "integration.created" do
      before { mastercard_service.create_or_update(**args) }
    end

    context "when the provider already exists" do
      let!(:mastercard_provider) do
        create(:mastercard_provider, organization:, code:, merchant_id: "OLD", api_password: "old", webhook_secret: nil)
      end

      it "updates only the given attributes" do
        result = mastercard_service.create_or_update(organization:, id: mastercard_provider.id, webhook_secret: "GATEWAY_SECRET")

        expect(result).to be_success
        expect(result.mastercard_provider).to have_attributes(
          id: mastercard_provider.id,
          merchant_id: "OLD",
          api_password: "old",
          webhook_secret: "GATEWAY_SECRET"
        )
      end

      it_behaves_like "produces a security log", "integration.updated" do
        before { mastercard_service.create_or_update(**args) }
      end

      context "when the code changes" do
        let(:customer) { create(:customer, organization:, payment_provider: "mastercard", payment_provider_code: code) }

        before { create(:mastercard_customer, customer:, payment_provider: mastercard_provider) }

        it "updates the payment provider code of the customers" do
          mastercard_service.create_or_update(organization:, id: mastercard_provider.id, code: "mastercard_2")

          expect(customer.reload.payment_provider_code).to eq("mastercard_2")
        end
      end
    end

    context "with an invalid region" do
      it "returns a validation failure" do
        result = mastercard_service.create_or_update(**args, region: "us")

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:region]).to eq(["value_is_invalid"])
      end
    end
  end
end
