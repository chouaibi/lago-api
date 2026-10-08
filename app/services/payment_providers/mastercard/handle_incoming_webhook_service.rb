# frozen_string_literal: true

module PaymentProviders
  module Mastercard
    class HandleIncomingWebhookService < BaseService
      Result = BaseResult[:event]

      def initialize(organization_id:, body:, secret:, code: nil)
        @organization_id = organization_id
        @body = body
        @secret = secret
        @code = code

        super
      end

      def call
        payment_provider_result = PaymentProviders::FindService.call(
          organization_id:,
          code:,
          payment_provider_type: "mastercard"
        )
        return payment_provider_result unless payment_provider_result.success?

        webhook_secret = payment_provider_result.payment_provider.webhook_secret
        return result.service_failure!(code: "webhook_error", message: "Webhook secret is missing") if webhook_secret.blank?

        # NOTE: Notifications are not signed. On https notification URLs, the gateway sends the
        #       notification secret it generated as is, in the X-Notification-Secret header.
        unless ActiveSupport::SecurityUtils.secure_compare(webhook_secret, secret.to_s)
          return result.service_failure!(code: "webhook_error", message: "Invalid webhook secret")
        end

        PaymentProviders::Mastercard::HandleEventJob.perform_later(
          organization: payment_provider_result.payment_provider.organization,
          event: body
        )

        result.event = body
        result
      end

      private

      attr_reader :organization_id, :body, :secret, :code
    end
  end
end
