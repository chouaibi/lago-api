# frozen_string_literal: true

module PaymentProviders
  module Mastercard
    module Webhooks
      class PaymentCompletedService < BaseService
        PAYMENT_SERVICE_CLASS_MAP = {
          "Invoice" => Invoices::Payments::MastercardService,
          "PaymentRequest" => PaymentRequests::Payments::MastercardService
        }.freeze

        def initialize(organization_id:, event_json:)
          @organization_id = organization_id
          @event_json = event_json

          super
        end

        def call
          return result if transaction_id.blank?

          # NOTE: Transactions that were not initiated by Lago (e.g. from the gateway
          #       merchant administration) have no payment and are ignored.
          payment = find_payment
          return result unless payment&.payment_provider

          # NOTE: The notification is only a trigger, the outcome of the transaction is
          #       read back from the gateway.
          status = fetch_transaction_result(payment)
          return result unless status

          PAYMENT_SERVICE_CLASS_MAP.fetch(payment.payable_type).call!(
            :update_payment_status,
            organization_id:,
            provider_payment_id: transaction_id,
            status:
          )

          result
        end

        private

        attr_reader :organization_id, :event_json

        def event
          @event ||= JSON.parse(event_json)
        end

        # NOTE: A payment is identified by the gateway transaction that charged it.
        #       Its gateway order is its payable, and is shared by every payment attempt.
        def transaction_id
          event.dig("transaction", "id")
        end

        def find_payment
          Payment.find_by(
            organization_id:,
            provider_payment_id: transaction_id,
            payment_provider_id: PaymentProviders::MastercardProvider.where(organization_id:).select(:id)
          )
        end

        def fetch_transaction_result(payment)
          payment_provider = payment.payment_provider

          response = LagoHttpClient::Client
            .new("#{payment_provider.api_url}/order/#{payment.payable_id}/transaction/#{transaction_id}")
            .get(headers: payment_provider.api_headers)

          response["result"]
        rescue LagoHttpClient::HttpError => e
          Rails.logger.error("Mastercard transaction verification error: #{e.message}")
          nil
        end
      end
    end
  end
end
