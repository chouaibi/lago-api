# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::MastercardService do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "mastercard") }
  let(:mastercard_provider) { create(:mastercard_provider, organization:) }
  let(:mastercard_customer) { create(:mastercard_customer, customer:, payment_provider: mastercard_provider) }
  let(:invoice_1) do
    create(:invoice, organization:, customer:, total_amount_cents: 200, currency: "USD", ready_for_payment_processing: true)
  end
  let(:invoice_2) do
    create(:invoice, organization:, customer:, total_amount_cents: 599, currency: "USD", ready_for_payment_processing: true)
  end
  let(:dunning_campaign) { nil }
  let(:payment_request) do
    create(
      :payment_request,
      organization:,
      customer:,
      amount_cents: 799,
      amount_currency: "USD",
      invoices: [invoice_1, invoice_2],
      dunning_campaign:
    )
  end

  describe ".call(:update_payment_status)" do
    subject(:result) do
      described_class.call(:update_payment_status, organization_id: organization.id, provider_payment_id:, status:)
    end

    let(:provider_payment_id) { "transaction-1" }
    let(:status) { "CAPTURED" }
    let(:payment) do
      create(
        :payment,
        payable: payment_request,
        customer:,
        provider_payment_id: "transaction-1",
        status: "PENDING",
        payable_payment_status: "processing",
        payment_provider: mastercard_provider,
        payment_provider_customer: mastercard_customer
      )
    end

    before { payment }

    it "updates the payment, the payment request and the invoices" do
      expect(result).to be_success
      expect(result.payment).to have_attributes(status: "CAPTURED", payable_payment_status: "succeeded")
      expect(result.payable.reload).to have_attributes(payment_status: "succeeded", ready_for_payment_processing: false)
      expect(invoice_1.reload).to have_attributes(payment_status: "succeeded", total_paid_amount_cents: 200)
      expect(invoice_2.reload).to have_attributes(payment_status: "succeeded", total_paid_amount_cents: 599)
    end

    it "does not send a payment requested email" do
      expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
    end

    context "when the payment request belongs to a dunning campaign" do
      let(:customer) do
        create(
          :customer,
          organization:,
          payment_provider: "mastercard",
          last_dunning_campaign_attempt: 3,
          last_dunning_campaign_attempt_at: Time.current
        )
      end
      let(:dunning_campaign) { create(:dunning_campaign, organization:) }

      it "resets the customer dunning campaign counters for the payment request currency" do
        expect { result && customer.reload }
          .to change(customer, :last_dunning_campaign_attempt).to(0)
          .and change(customer, :last_dunning_campaign_attempt_at).to(nil)
          .and change(customer, :dunning_currency_attempts).to({"USD" => 0})
      end
    end

    context "when the payment failed" do
      let(:status) { "DECLINED" }

      it "marks the payment request and the invoices as failed" do
        expect(result).to be_success
        expect(result.payable.reload).to have_attributes(payment_status: "failed", ready_for_payment_processing: true)
        expect(invoice_1.reload.payment_status).to eq("failed")
        expect(invoice_2.reload.payment_status).to eq("failed")
      end

      it "sends a payment requested email" do
        expect { result }.to have_enqueued_mail(PaymentRequestMailer, :requested)
          .with(params: {payment_request:}, args: [])
      end
    end

    context "when the payment request is already paid" do
      let(:payment_request) do
        create(:payment_request, organization:, customer:, invoices: [invoice_1], payment_status: "succeeded")
      end

      it "does not update the payment" do
        expect { result }.not_to change { payment.reload.status }
        expect(result).to be_success
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
