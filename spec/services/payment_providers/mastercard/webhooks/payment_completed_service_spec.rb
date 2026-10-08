# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Mastercard::Webhooks::PaymentCompletedService do
  subject(:payment_completed_service) { described_class.new(organization_id: organization.id, event_json:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "mastercard") }
  let(:mastercard_provider) { create(:mastercard_provider, organization:) }
  let(:mastercard_customer) { create(:mastercard_customer, customer:, payment_provider: mastercard_provider) }
  let(:invoice) { create(:invoice, organization:, customer:, total_amount_cents: 1_000, currency: "USD") }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      customer:,
      payment_provider: mastercard_provider,
      payment_provider_customer: mastercard_customer,
      provider_payment_id: "transaction-1",
      status: "PENDING",
      payable_payment_status: "processing"
    )
  end
  let(:transaction_id) { "transaction-1" }
  let(:event_json) do
    {result: "SUCCESS", order: {id: invoice.id, status: "CAPTURED"}, transaction: {id: transaction_id, type: "PAYMENT"}}.to_json
  end
  let(:transaction_url) { "#{mastercard_provider.api_url}/order/#{invoice.id}/transaction/transaction-1" }
  let(:transaction_result) { "SUCCESS" }

  before do
    payment
    stub_request(:get, transaction_url).to_return(status: 200, body: {result: transaction_result, transaction: {id: "transaction-1"}}.to_json)
  end

  describe "#call" do
    it "updates the payment with the transaction result read back from the gateway" do
      expect(payment_completed_service.call).to be_success

      expect(WebMock).to have_requested(:get, transaction_url).with(headers: mastercard_provider.api_headers)
      expect(payment.reload).to have_attributes(status: "SUCCESS", payable_payment_status: "succeeded")
      expect(invoice.reload).to be_payment_succeeded
    end

    context "when the transaction failed" do
      let(:transaction_result) { "FAILURE" }

      it "marks the payment as failed" do
        payment_completed_service.call

        expect(payment.reload.payable_payment_status).to eq("failed")
        expect(invoice.reload).to be_payment_failed
      end
    end

    context "when the payment was created by the automatic charge" do
      let(:payment) do
        create(
          :payment,
          payable: invoice,
          customer:,
          payment_provider: mastercard_provider,
          payment_provider_customer: mastercard_customer,
          payment_method: create(:payment_method, payment_provider_customer: mastercard_customer, provider_method_id: "9999000011112222"),
          amount_cents: 1_000,
          amount_currency: "USD",
          provider_payment_id: nil
        )
      end
      let(:charged_transaction_id) { payment.reload.provider_payment_id }
      let(:transaction_id) { charged_transaction_id }
      let(:transaction_url) { %r{/order/#{invoice.id}/transaction/[0-9a-f-]{36}\z} }

      before do
        mastercard_customer.update!(agreement_id: "agreement-1")

        # NOTE: The gateway echoes the transaction id chosen by Lago, and the charge stays pending.
        stub_request(:put, %r{/order/#{invoice.id}/transaction/[0-9a-f-]{36}\z}).to_return do |request|
          {status: 200, body: {result: "PENDING", transaction: {id: request.uri.path.split("/").last}}.to_json}
        end

        PaymentProviders::Mastercard::Payments::CreateService.new(payment:, reference: "ref", metadata: {}).call
      end

      it "finds the payment from the notified transaction" do
        expect(payment.reload.payable_payment_status).to eq("processing")

        payment_completed_service.call

        expect(payment.reload.payable_payment_status).to eq("succeeded")
        expect(invoice.reload).to be_payment_succeeded
      end
    end

    context "when the transaction was not initiated by Lago" do
      let(:transaction_id) { "unknown" }

      it "ignores the notification" do
        expect(payment_completed_service.call).to be_success

        expect(WebMock).not_to have_requested(:get, /gateway/)
        expect(payment.reload.payable_payment_status).to eq("processing")
      end
    end

    context "when the payment belongs to another organization" do
      subject(:payment_completed_service) { described_class.new(organization_id: create(:organization).id, event_json:) }

      it "ignores the notification" do
        payment_completed_service.call

        expect(payment.reload.payable_payment_status).to eq("processing")
      end
    end

    context "when the gateway cannot be reached" do
      before { stub_request(:get, transaction_url).to_return(status: 500, body: "") }

      it "does not update the payment" do
        expect(payment_completed_service.call).to be_success

        expect(payment.reload.payable_payment_status).to eq("processing")
      end
    end

    context "with a payment request" do
      let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice]) }
      let(:payment) do
        create(
          :payment,
          payable: payment_request,
          customer:,
          payment_provider: mastercard_provider,
          payment_provider_customer: mastercard_customer,
          provider_payment_id: "transaction-1",
          payable_payment_status: "processing"
        )
      end
      let(:transaction_url) { "#{mastercard_provider.api_url}/order/#{payment_request.id}/transaction/transaction-1" }

      it "updates the payment request" do
        payment_completed_service.call

        expect(payment_request.reload).to be_payment_succeeded
        expect(invoice.reload).to be_payment_succeeded
      end
    end
  end
end
