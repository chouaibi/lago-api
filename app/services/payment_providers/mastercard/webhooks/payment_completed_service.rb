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
          order_id = event.dig("order", "id")
          return result unless order_id

          payment_provider_result = PaymentProviders::FindService.call(
            organization_id:,
            payment_provider_type: "mastercard"
          )
          return result unless payment_provider_result.success?

          # NOTE: The notification is only a trigger, the status is read back from the gateway.
          status = fetch_order_status(payment_provider_result.payment_provider, order_id)
          return result unless status

          payable = Invoice.find_by(id: order_id) || PaymentRequest.find_by(id: order_id)
          return result unless payable

          PAYMENT_SERVICE_CLASS_MAP.fetch(payable.class.name).call!(
            :update_payment_status,
            organization_id:,
            provider_payment_id: order_id,
            status:
          )

          result
        end

        private

        attr_reader :organization_id, :event_json

        def event
          @event ||= JSON.parse(event_json)
        end

        def fetch_order_status(payment_provider, order_id)
          response = LagoHttpClient::Client.new("#{payment_provider.api_url}/order/#{order_id}")
            .get(headers: payment_provider.api_headers)

          response.dig("order", "status") || response["result"]
        rescue LagoHttpClient::HttpError => e
          Rails.logger.error("Mastercard order verification error: #{e.message}")
          nil
        end
      end
    end
  end
end
