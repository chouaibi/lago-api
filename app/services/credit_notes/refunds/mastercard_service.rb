# frozen_string_literal: true

module CreditNotes
  module Refunds
    class MastercardService < BaseService
      Result = BaseResult[:credit_note, :refund]

      include Customers::PaymentProviderFinder

      def initialize(credit_note = nil)
        @credit_note = credit_note

        super
      end

      def create
        result.credit_note = credit_note
        return result unless should_process_refund?

        mastercard_response = create_mastercard_refund

        refund = Refund.new(
          organization_id: credit_note.organization_id,
          credit_note:,
          refundable: credit_note,
          reason: :credit_note,
          payment:,
          payment_provider: payment.payment_provider,
          payment_provider_customer: payment_provider_customer(payment),
          amount_cents: credit_note.refund_amount_cents,
          amount_currency: credit_note.credit_amount_currency.upcase,
          status: "pending",
          provider_refund_id: mastercard_response.dig("transaction", "id")
        )
        refund.save!

        update_credit_note_status(refund.status)
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        result.refund = refund
        result
      end

      def update_status(provider_refund_id:, status:, metadata: {})
        refund = Refund.find_by(provider_refund_id:)
        return handle_missing_refund(metadata) unless refund

        result.refund = refund
        @credit_note = result.credit_note = refund.credit_note
        return result if refund.credit_note.succeeded?

        refund.update!(status:)
        update_credit_note_status(status)
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        if status.to_sym == :failed
          deliver_error_webhook(message: "Payment refund failed", code: nil)
          Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")
          result.service_failure!(code: "refund_failed", message: "Refund failed to perform")
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_accessor :credit_note

      delegate :organization, :invoice, to: :credit_note

      def should_process_refund?
        return false if !credit_note.refunded? || credit_note.succeeded? || invoice.payment_dispute_lost_at?

        payment.present?
      end

      def payment
        @payment ||= invoice.refundable_payment
      end

      def mastercard_payment_provider
        payment.payment_provider
      end

      # NOTE: The gateway order of a payment is its payable (invoice or payment request).
      def create_mastercard_refund
        response = LagoHttpClient::Client.new(
          "#{mastercard_payment_provider.api_url}/order/#{payment.payable_id}/transaction/#{SecureRandom.uuid}"
        ).put_with_response(refund_body, mastercard_payment_provider.api_headers)

        JSON.parse(response.body)
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(message: e.error_body, code: e.error_code)
        update_credit_note_status(:failed)
        Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")

        raise
      end

      def refund_body
        {
          apiOperation: "REFUND",
          transaction: {
            amount: Money.from_cents(credit_note.refund_amount_cents, credit_note.credit_amount_currency).format(
              symbol: false, no_cents: false, thousands_separator: "", decimal_mark: "."
            ),
            currency: credit_note.credit_amount_currency.upcase,
            reference: credit_note.id
          }
        }
      end

      def deliver_error_webhook(message:, code:)
        SendWebhookJob.perform_later(
          "credit_note.provider_refund_failure",
          credit_note,
          provider_customer_id: payment_provider_customer(payment)&.provider_customer_id,
          provider_error: {
            message:,
            error_code: code
          }
        )
      end

      def update_credit_note_status(status)
        credit_note.refund_status = status
        credit_note.refunded_at = Time.current if credit_note.succeeded?
        credit_note.save!
      end

      def handle_missing_refund(metadata)
        # NOTE: Refund was not initiated by lago
        return result unless metadata&.key?(:lago_invoice_id)

        # NOTE: Invoice does not belongs to this lago instance
        return result unless Invoice.find_by(id: metadata[:lago_invoice_id])

        result.not_found_failure!(resource: "mastercard_refund")
      end
    end
  end
end
