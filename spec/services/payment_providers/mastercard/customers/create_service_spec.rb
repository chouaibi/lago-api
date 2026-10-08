# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Mastercard::Customers::CreateService do
  subject(:create_service) { described_class.new(customer:, payment_provider_id: mastercard_provider.id, params:) }

  let(:customer) { create(:customer) }
  let(:mastercard_provider) { create(:mastercard_provider, organization: customer.organization) }
  let(:params) { {sync_with_provider: true} }

  describe "#call" do
    it "creates a mastercard customer without provider customer id" do
      result = create_service.call

      expect(result).to be_success
      expect(result.provider_customer).to be_a(PaymentProviderCustomers::MastercardCustomer)
      expect(result.provider_customer).to have_attributes(
        customer_id: customer.id,
        organization_id: customer.organization_id,
        payment_provider_id: mastercard_provider.id,
        provider_customer_id: nil,
        code: mastercard_provider.code,
        sync_with_provider: true
      )
    end

    context "when the mastercard customer already exists" do
      let!(:mastercard_customer) { create(:mastercard_customer, customer:, payment_provider: mastercard_provider) }

      it "updates it" do
        result = create_service.call

        expect(result.provider_customer.id).to eq(mastercard_customer.id)
        expect(result.provider_customer.sync_with_provider).to be(true)
      end
    end
  end
end
