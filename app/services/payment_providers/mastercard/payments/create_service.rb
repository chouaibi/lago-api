# frozen_string_literal: true

module PaymentProviders
  module Mastercard
    module Payments
      # Charges a stored card token with a merchant-initiated transaction (MIT).
      #
      # The PAY request replays the credential-on-file agreement established when the
      # card was saved, otherwise the gateway rejects it.
      class CreateService < BaseService
        Result = BaseResult[:payment, :error_message, :error_code, :reraise, :should_retry]

        AGREEMENT_TYPE = "UNSCHEDULED"

        def initialize(payment:, reference:, metadata:)
          @payment = payment
          @reference = reference
          @metadata = metadata
          @invoice = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment

          if token.blank?
            return prepare_pending_result(
              code: "missing_mastercard_token",
              message: "Customer has no stored Mastercard card token"
            )
          end

          if provider_customer.agreement_id.blank?
            return prepare_pending_result(
              code: "missing_agreement_id",
              message: "Customer has no stored Mastercard credential-on-file agreement"
            )
          end

          response = LagoHttpClient::Client.new(charge_url).put_with_response(charge_payload, payment_provider.api_headers)
          parsed = JSON.parse(response.body)

          payment.provider_payment_id = parsed.dig("transaction", "id") || transaction_id
          payment.status = parsed["result"]
          payment.payable_payment_status = payment_provider.determine_payment_status(payment.status)
          payment.save!

          result.payment = payment
          result
        rescue LagoHttpClient::HttpError => e
          prepare_failed_result(e)
        end

        private

        attr_reader :payment, :reference, :metadata, :invoice, :provider_customer

        delegate :payment_provider, to: :payment

        # NOTE: The payment method selected for the payment takes precedence over the default one.
        def token
          @token ||= payment.payment_method&.provider_method_id || provider_customer.token
        end

        # NOTE: The transaction id identifies the payment in the gateway notifications.
        def transaction_id
          @transaction_id ||= SecureRandom.uuid
        end

        def charge_url
          "#{payment_provider.api_url}/order/#{invoice.id}/transaction/#{transaction_id}"
        end

        def charge_payload
          {
            apiOperation: "PAY",
            agreement: {
              id: provider_customer.agreement_id,
              type: AGREEMENT_TYPE
            },
            sourceOfFunds: {
              type: "CARD",
              token:,
              provided: {
                card: {storedOnFile: "STORED"}
              }
            },
            order: {
              amount: amount,
              currency: payment.amount_currency.upcase,
              reference: invoice.number,
              description: reference
            },
            transaction: {
              reference: invoice.number,
              source: "MERCHANT"
            }
          }
        end

        # NOTE: The gateway expects the amount in major units, as a decimal string.
        def amount
          Money.from_cents(payment.amount_cents, payment.amount_currency).format(
            symbol: false, no_cents: false, thousands_separator: "", decimal_mark: "."
          )
        end

        def prepare_pending_result(code:, message:)
          payment.update!(payable_payment_status: :pending)

          result.error_message = message
          result.error_code = code
          result.service_failure!(code:, message:)
        end

        def prepare_failed_result(error)
          payment.update!(status: :failed, payable_payment_status: :failed, error_code: error.error_code)

          result.error_message = error.error_body
          result.error_code = error.error_code
          result.service_failure!(code: "mastercard_error", message: "#{error.error_code}: #{error.error_body}")
        end
      end
    end
  end
end
