# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Mastercard::Payments::CreateService do
  subject(:create_service) { described_class.new(payment:, reference:, metadata: {lago_invoice_id: invoice.id}) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "mastercard") }
  let(:mastercard_provider) { create(:mastercard_provider, organization:, merchant_id: "MERCHANT1") }
  let(:mastercard_customer) do
    create(:mastercard_customer, customer:, payment_provider: mastercard_provider, token: "9999000011112222", agreement_id:)
  end
  let(:agreement_id) { "agreement-1" }
  let(:invoice) { create(:invoice, organization:, customer:, total_amount_cents: 10_050, currency: "USD") }
  let(:payment_method) { nil }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      customer:,
      status: "pending",
      payment_provider: mastercard_provider,
      payment_provider_customer: mastercard_customer,
      payment_method:,
      amount_cents: invoice.total_amount_cents,
      amount_currency: invoice.currency,
      provider_payment_id: nil
    )
  end
  let(:reference) { "Billing Entity - Invoice #{invoice.number}" }
  let(:charge_url) { %r{\Ahttps://eu-gateway\.mastercard\.com/api/rest/version/100/merchant/MERCHANT1/order/#{invoice.id}/transaction/[0-9a-f-]{36}\z} }
  let(:response_body) do
    {
      result: "SUCCESS",
      order: {id: invoice.id, status: "CAPTURED"},
      transaction: {id: "transaction-1", type: "PAYMENT"},
      response: {gatewayCode: "APPROVED"}
    }
  end

  before do
    stub_request(:put, charge_url).to_return(status: 200, body: response_body.to_json, headers: {"Content-Type" => "application/json"})
  end

  describe "#call" do
    it "charges the stored card with a merchant-initiated transaction" do
      create_service.call

      expect(WebMock).to have_requested(:put, charge_url).with(
        headers: {"Authorization" => "Basic #{Base64.strict_encode64("merchant.MERCHANT1:#{mastercard_provider.api_password}")}"},
        body: {
          apiOperation: "PAY",
          agreement: {id: "agreement-1", type: "UNSCHEDULED"},
          sourceOfFunds: {type: "CARD", token: "9999000011112222", provided: {card: {storedOnFile: "STORED"}}},
          order: {amount: "100.50", currency: "USD", reference: invoice.number, description: reference},
          transaction: {reference: invoice.number, source: "MERCHANT"}
        }.to_json
      )
    end

    it "updates the payment" do
      result = create_service.call

      expect(result).to be_success
      expect(result.payment).to have_attributes(
        provider_payment_id: payment.id,
        status: "SUCCESS",
        payable_payment_status: "succeeded"
      )
    end

    context "when the payable is a payment request" do
      let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice], amount_cents: 10_050, amount_currency: "USD") }
      let(:payment) do
        create(
          :payment,
          payable: payment_request,
          customer:,
          payment_provider: mastercard_provider,
          payment_provider_customer: mastercard_customer,
          amount_cents: 10_050,
          amount_currency: "USD",
          provider_payment_id: nil
        )
      end
      let(:charge_url) { %r{/order/#{payment_request.id}/transaction/[0-9a-f-]{36}\z} }

      it "charges the payment request order" do
        result = create_service.call

        expect(result).to be_success
        expect(WebMock).to have_requested(:put, charge_url).with { |request|
          body = JSON.parse(request.body)
          body.dig("order", "reference") == payment_request.id && body.dig("transaction", "reference") == payment_request.id
        }
      end
    end

    context "when the invoice gates a subscription" do
      let(:subscription) do
        create(:subscription, :incomplete, :with_activation_rules,
          activation_rules_config: [{type: "payment", timeout_hours: 48, status: "pending"}],
          customer:, organization:)
      end
      let(:invoice) { create(:invoice, organization:, customer:, total_amount_cents: 10_050, currency: "USD", status: :open) }

      before { create(:invoice_subscription, invoice:, subscription:) }

      it "references the invoice by its id" do
        create_service.call

        expect(WebMock).to have_requested(:put, charge_url).with { |request|
          JSON.parse(request.body).dig("order", "reference") == invoice.id
        }
      end
    end

    context "when a payment method is selected for the payment" do
      let(:payment_method) { create(:payment_method, payment_provider_customer: mastercard_customer, provider_method_id: "5555000011112222", is_default: false) }

      it "charges the selected card" do
        create_service.call

        expect(WebMock).to have_requested(:put, charge_url).with { |request|
          JSON.parse(request.body).dig("sourceOfFunds", "token") == "5555000011112222"
        }
      end
    end

    context "when the gateway declines the payment" do
      let(:response_body) do
        {
          result: "FAILURE",
          order: {id: invoice.id, status: "FAILED"},
          transaction: {id: "transaction-1", type: "PAYMENT"},
          response: {gatewayCode: "DECLINED"}
        }
      end

      it "marks the payment as failed" do
        result = create_service.call

        expect(result.payment).to have_attributes(provider_payment_id: payment.id, status: "FAILURE", payable_payment_status: "failed")
      end
    end

    context "when the gateway rejects the request" do
      before do
        stub_request(:put, charge_url).to_return(status: 400, body: {error: {cause: "INVALID_REQUEST"}}.to_json)
      end

      it "marks the payment as failed and returns a service failure" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("mastercard_error")
        expect(result.error_code).to eq("400")
        expect(result.payment).to have_attributes(status: "failed", payable_payment_status: "failed")
      end
    end

    context "when the gateway answer is lost" do
      let(:transaction_url) { "#{mastercard_provider.api_url}/order/#{invoice.id}/transaction/#{payment.id}" }

      before do
        stub_request(:put, charge_url).to_raise(Net::ReadTimeout).then
          .to_return(status: 200, body: response_body.to_json)
        stub_request(:get, transaction_url).to_return(status: 404, body: {result: "ERROR", error: {cause: "INVALID_REQUEST"}}.to_json)
      end

      it "keeps the payment pending with its transaction id and raises a connection error" do
        expect { create_service.call }.to raise_error(Invoices::Payments::ConnectionError)

        expect(payment.reload).to have_attributes(provider_payment_id: payment.id, payable_payment_status: "pending")
      end

      it "retries the PAY request with the same transaction id" do
        expect { create_service.call }.to raise_error(Invoices::Payments::ConnectionError)

        result = described_class.new(payment: payment.reload, reference:, metadata: {}).call

        expect(result).to be_success
        expect(result.payment).to have_attributes(provider_payment_id: payment.id, payable_payment_status: "succeeded")
        expect(WebMock).to have_requested(:get, transaction_url).once
        expect(WebMock).to have_requested(:put, transaction_url).twice
        expect(WebMock).to have_requested(:put, charge_url).twice
      end
    end

    context "when the payment already has a transaction" do
      let(:payment) do
        create(
          :payment,
          payable: invoice,
          customer:,
          payment_provider: mastercard_provider,
          payment_provider_customer: mastercard_customer,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency,
          provider_payment_id: "transaction-0",
          payable_payment_status: "pending"
        )
      end
      let(:transaction_url) { "#{mastercard_provider.api_url}/order/#{invoice.id}/transaction/transaction-0" }

      before do
        stub_request(:get, transaction_url).to_return(
          status: 200,
          body: {result: "SUCCESS", order: {id: invoice.id}, transaction: {id: "transaction-0", type: "PAYMENT"}}.to_json
        )
      end

      it "reconciles the existing transaction without charging again" do
        result = create_service.call

        expect(result).to be_success
        expect(result.payment).to have_attributes(provider_payment_id: "transaction-0", status: "SUCCESS", payable_payment_status: "succeeded")
        expect(WebMock).not_to have_requested(:put, charge_url)
      end

      context "when the gateway cannot read the transaction back" do
        before { stub_request(:get, transaction_url).to_return(status: 503, body: "") }

        it "raises a connection error without charging" do
          expect { create_service.call }.to raise_error(Invoices::Payments::ConnectionError)

          expect(WebMock).not_to have_requested(:put, charge_url)
          expect(payment.reload.payable_payment_status).to eq("pending")
        end
      end
    end

    context "when the gateway answers with a server error" do
      before { stub_request(:put, charge_url).to_return(status: 502, body: "") }

      it "keeps the payment pending and raises a connection error" do
        expect { create_service.call }.to raise_error(Invoices::Payments::ConnectionError)

        expect(payment.reload).to have_attributes(provider_payment_id: payment.id, payable_payment_status: "pending")
      end
    end

    context "without agreement id" do
      let(:agreement_id) { nil }

      it "leaves the payment pending without calling the gateway" do
        result = create_service.call

        expect(WebMock).not_to have_requested(:put, charge_url)
        expect(result).not_to be_success
        expect(result.error_code).to eq("missing_agreement_id")
        expect(result.payment.payable_payment_status).to eq("pending")
      end
    end

    context "without stored card token" do
      let(:mastercard_customer) { create(:mastercard_customer, customer:, payment_provider: mastercard_provider, agreement_id:) }

      it "leaves the payment pending without calling the gateway" do
        result = create_service.call

        expect(WebMock).not_to have_requested(:put, charge_url)
        expect(result).not_to be_success
        expect(result.error_code).to eq("missing_mastercard_token")
        expect(result.payment.payable_payment_status).to eq("pending")
      end
    end
  end
end
