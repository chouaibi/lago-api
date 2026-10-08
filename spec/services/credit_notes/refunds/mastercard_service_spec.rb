# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::Refunds::MastercardService do
  subject(:mastercard_service) { described_class.new(credit_note) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "mastercard") }
  let(:mastercard_provider) { create(:mastercard_provider, organization:, merchant_id: "MERCHANT1") }
  let(:mastercard_customer) { create(:mastercard_customer, customer:, payment_provider: mastercard_provider) }
  let(:invoice) do
    create(:invoice, organization:, customer:, total_amount_cents: 200, currency: "CHF", payment_status: "succeeded")
  end
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      customer:,
      payment_provider: mastercard_provider,
      payment_provider_customer: mastercard_customer,
      amount_cents: 200,
      amount_currency: "CHF",
      provider_payment_id: "transaction-1",
      payable_payment_status: "succeeded"
    )
  end
  let(:credit_note) do
    create(
      :credit_note,
      invoice:,
      customer:,
      credit_amount_currency: "CHF",
      refund_amount_cents: 134,
      refund_amount_currency: "CHF",
      refund_status: :pending
    )
  end
  let(:refund_url) do
    %r{\Ahttps://eu-gateway\.mastercard\.com/api/rest/version/100/merchant/MERCHANT1/order/#{invoice.id}/transaction/[0-9a-f-]{36}\z}
  end

  describe "#create" do
    before do
      payment

      stub_request(:put, refund_url).to_return(
        status: 200,
        body: {result: "SUCCESS", transaction: {id: "refund-transaction-1", type: "REFUND"}}.to_json
      )
    end

    it "refunds the payment on the gateway order" do
      mastercard_service.create

      expect(WebMock).to have_requested(:put, refund_url).with(
        body: {
          apiOperation: "REFUND",
          transaction: {amount: "1.34", currency: "CHF", reference: credit_note.id}
        }.to_json
      )
    end

    it "creates a pending refund" do
      result = mastercard_service.create

      expect(result).to be_success
      expect(result.refund).to have_attributes(
        organization_id: organization.id,
        credit_note:,
        refundable: credit_note,
        reason: "credit_note",
        payment:,
        payment_provider: mastercard_provider,
        payment_provider_customer: mastercard_customer,
        amount_cents: 134,
        amount_currency: "CHF",
        status: "pending",
        provider_refund_id: "refund-transaction-1"
      )
      expect(result.credit_note.reload).to be_pending
    end

    it "tracks the refund status" do
      allow(Utils::SegmentTrack).to receive(:refund_status_changed)

      mastercard_service.create

      expect(Utils::SegmentTrack).to have_received(:refund_status_changed).with("pending", credit_note.id, organization.id)
    end

    context "when the invoice was paid through a payment request" do
      let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice], payment_status: "succeeded") }
      let(:payment) do
        create(
          :payment,
          payable: payment_request,
          customer:,
          payment_provider: mastercard_provider,
          payment_provider_customer: mastercard_customer,
          payable_payment_status: "succeeded"
        )
      end
      let(:refund_url) { %r{/order/#{payment_request.id}/transaction/[0-9a-f-]{36}\z} }

      it "refunds the payment on the payment request order" do
        result = mastercard_service.create

        expect(result).to be_success
        expect(result.refund.payment).to eq(payment)
        expect(WebMock).to have_requested(:put, refund_url)
      end
    end

    context "when the gateway rejects the refund" do
      before do
        stub_request(:put, refund_url).to_return(status: 400, body: {error: {cause: "INVALID_REQUEST"}}.to_json)
      end

      it "marks the credit note refund as failed and raises" do
        expect { mastercard_service.create }.to raise_error(LagoHttpClient::HttpError)

        expect(credit_note.reload).to be_failed
        expect(Refund.count).to eq(0)
      end

      it "enqueues a provider refund failure webhook" do
        expect { mastercard_service.create }
          .to raise_error(LagoHttpClient::HttpError)
          .and have_enqueued_job(SendWebhookJob).with("credit_note.provider_refund_failure", credit_note, Hash)
      end
    end

    context "when the credit note has no refund amount" do
      let(:credit_note) { create(:credit_note, invoice:, customer:, refund_amount_cents: 0, refund_status: nil) }

      it "does not call the gateway" do
        result = mastercard_service.create

        expect(result).to be_success
        expect(result.refund).to be_nil
        expect(WebMock).not_to have_requested(:put, refund_url)
      end
    end

    context "without succeeded payment" do
      let(:payment) { nil }

      it "does not call the gateway" do
        result = mastercard_service.create

        expect(result.refund).to be_nil
        expect(WebMock).not_to have_requested(:put, refund_url)
      end
    end
  end

  describe "#update_status" do
    subject(:mastercard_service) { described_class.new }

    let(:refund) do
      create(:refund, credit_note:, payment:, payment_provider: mastercard_provider, provider_refund_id: "refund-transaction-1")
    end
    let(:status) { :succeeded }

    before { refund }

    it "updates the refund and the credit note" do
      result = mastercard_service.update_status(provider_refund_id: "refund-transaction-1", status:)

      expect(result).to be_success
      expect(result.refund.reload.status).to eq("succeeded")
      expect(result.credit_note.reload).to have_attributes(refund_status: "succeeded", refunded_at: be_present)
    end

    context "when the refund failed" do
      let(:status) { :failed }

      it "marks the credit note refund as failed" do
        result = mastercard_service.update_status(provider_refund_id: "refund-transaction-1", status:)

        expect(result).not_to be_success
        expect(result.error.code).to eq("refund_failed")
        expect(credit_note.reload).to be_failed
      end

      it "enqueues a provider refund failure webhook" do
        expect { mastercard_service.update_status(provider_refund_id: "refund-transaction-1", status:) }
          .to have_enqueued_job(SendWebhookJob).with("credit_note.provider_refund_failure", credit_note, Hash)
      end
    end

    context "when the refund is not found" do
      it "ignores refunds not initiated by Lago" do
        result = mastercard_service.update_status(provider_refund_id: "unknown", status:)

        expect(result).to be_success
        expect(result.refund).to be_nil
      end

      it "returns a not found failure for invoices of this instance" do
        result = mastercard_service.update_status(
          provider_refund_id: "unknown",
          status:,
          metadata: {lago_invoice_id: invoice.id}
        )

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("mastercard_refund_not_found")
      end
    end
  end
end
