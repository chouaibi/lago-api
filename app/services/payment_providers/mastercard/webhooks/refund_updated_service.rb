# frozen_string_literal: true

module PaymentProviders
  module Mastercard
    module Webhooks
      class RefundUpdatedService < BaseService
        # NOTE: The outcome of the REFUND transaction is the top-level `result` of the notification.
        STATUS_MAP = {
          "SUCCESS" => :succeeded,
          "FAILURE" => :failed,
          "PENDING" => :pending
        }.freeze

        def initialize(organization_id:, event_json:)
          @organization_id = organization_id
          @event_json = event_json

          super
        end

        def call
          status = STATUS_MAP[event["result"]]
          return result unless status

          provider_refund_id = event.dig("transaction", "id")
          return result unless provider_refund_id

          CreditNotes::Refunds::MastercardService.new.update_status(
            provider_refund_id:,
            status:,
            metadata: {lago_invoice_id: event.dig("order", "id")}
          ).raise_if_error!

          result
        end

        private

        attr_reader :organization_id, :event_json

        def event
          @event ||= JSON.parse(event_json)
        end
      end
    end
  end
end
