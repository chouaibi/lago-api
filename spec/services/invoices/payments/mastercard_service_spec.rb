# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::MastercardService do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "mastercard") }
  let(:mastercard_provider) { create(:mastercard_provider, organization:) }
  let(:mastercard_customer) { create(:mastercard_customer, customer:, payment_provider: mastercard_provider) }
  let(:invoice) do
    create(:invoice, organization:, customer:, total_amount_cents: 200, currency: "EUR", ready_for_payment_processing: true)
  end

  describe ".call(:update_payment_status)" do
    subject(:result) do
      described_class.call(:update_payment_status, organization_id: organization.id, provider_payment_id:, status:)
    end

    let(:provider_payment_id) { "transaction-1" }
    let(:status) { "SUCCESS" }
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        customer:,
        provider_payment_id: "transaction-1",
        status: "PENDING",
        payable_payment_status: "processing",
        payment_provider: mastercard_provider,
        payment_provider_customer: mastercard_customer
      )
    end

    before { payment }

    it "updates the payment and the invoice payment status" do
      expect(result).to be_success
      expect(result.payment).to have_attributes(status: "SUCCESS", payable_payment_status: "succeeded")
      expect(result.invoice.reload).to have_attributes(
        payment_status: "succeeded",
        ready_for_payment_processing: false,
        total_paid_amount_cents: 200
      )
    end

    it "enqueues a payment.succeeded webhook" do
      expect { result }.to have_enqueued_job(SendWebhookJob).with("payment.succeeded", Payment)
    end

    it_behaves_like "syncs payment" do
      let(:service_call) { result }
    end

    context "when the payment failed" do
      let(:status) { "FAILURE" }

      it "marks the invoice as failed" do
        expect(result).to be_success
        expect(result.payment.payable_payment_status).to eq("failed")
        expect(result.invoice.reload).to have_attributes(payment_status: "failed", ready_for_payment_processing: true)
      end

      it "does not enqueue a payment.succeeded webhook" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob).with("payment.succeeded", Payment)
      end
    end

    context "when the invoice is already paid" do
      let(:invoice) { create(:invoice, organization:, customer:, payment_status: "succeeded") }

      it "does not update the payment" do
        expect { result }.not_to change { payment.reload.status }
        expect(result).to be_success
      end
    end

    context "when the payment belongs to another organization" do
      let(:result) do
        described_class.call(:update_payment_status, organization_id: create(:organization).id, provider_payment_id:, status:)
      end

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("mastercard_payment_not_found")
      end
    end

    context "when the payment is not found" do
      let(:provider_payment_id) { "unknown" }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("mastercard_payment_not_found")
      end
    end
  end
end
