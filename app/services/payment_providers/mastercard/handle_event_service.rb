# frozen_string_literal: true

module PaymentProviders
  module Mastercard
    class HandleEventService < BaseService
      # NOTE: A notification carries the order and transaction it is about, not an event name.
      #       It is routed on the type of the transaction.
      REFUND_TRANSACTION_TYPE = "REFUND"
      PAYMENT_TRANSACTION_TYPES = %w[AUTHORIZATION PAYMENT CAPTURE].freeze

      def initialize(organization:, event_json:)
        @organization = organization
        @event_json = event_json

        super
      end

      def call
        service_class = service_for(event.dig("transaction", "type"))
        return result unless service_class

        begin
          service_class.call!(organization_id: organization.id, event_json:)
        rescue => e
          Rails.logger.error("Mastercard event processing error: #{e.message}")
        end

        result
      end

      private

      attr_reader :organization, :event_json

      def service_for(transaction_type)
        case transaction_type
        when REFUND_TRANSACTION_TYPE
          PaymentProviders::Mastercard::Webhooks::RefundUpdatedService
        when *PAYMENT_TRANSACTION_TYPES
          PaymentProviders::Mastercard::Webhooks::PaymentCompletedService
        end
      end

      def event
        @event ||= JSON.parse(event_json)
      end
    end
  end
end
