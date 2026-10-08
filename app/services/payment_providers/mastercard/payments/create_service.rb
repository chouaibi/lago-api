# frozen_string_literal: true

module PaymentProviders
  module Mastercard
    module Payments
      # Charges a stored card token with a merchant-initiated transaction (MIT).
      #
      # The PAY request replays the credential-on-file agreement established when the
      # card was saved, otherwise the gateway rejects it.
      #
      # The charge is idempotent across retries: the gateway transaction id is derived from
      # the payment and stored on it before the PAY request. When the payment already has
      # one (the previous attempt lost its answer), the transaction is read back first and
      # the PAY request is only sent again, with the same transaction id, if it does not exist.
      class CreateService < BaseService
        Result = BaseResult[:payment, :error_message, :error_code, :reraise, :should_retry]

        AGREEMENT_TYPE = "UNSCHEDULED"

        # NOTE: The outcome of a request that raised one of these errors is unknown.
        CONNECTION_ERRORS = LagoHttpClient::Client::TRANSIENT_ERROR_CLASSES + [Timeout::Error, SocketError]

        def initialize(payment:, reference:, metadata:)
          @payment = payment
          @reference = reference
          @metadata = metadata
          @payable = payment.payable
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

          retrying = payment.provider_payment_id.present?
          payment.update!(provider_payment_id: transaction_id) unless retrying

          transaction = (retrying && fetch_transaction) || create_transaction

          payment.status = transaction["result"]
          payment.payable_payment_status = payment_provider.determine_payment_status(payment.status)
          payment.save!

          result.payment = payment
          result
        rescue LagoHttpClient::HttpError => e
          # NOTE: A server error leaves the outcome unknown, like a connection error.
          raise Invoices::Payments::ConnectionError, e if server_error?(e)

          prepare_failed_result(e)
        rescue *CONNECTION_ERRORS => e
          # NOTE: Allow auto-retry, the retry reuses the transaction id of the payment.
          raise Invoices::Payments::ConnectionError, e
        end

        private

        attr_reader :payment, :reference, :metadata, :payable, :provider_customer

        delegate :payment_provider, to: :payment

        # NOTE: The payment method selected for the payment takes precedence over the default one.
        def token
          @token ||= payment.payment_method&.provider_method_id || provider_customer.token
        end

        # NOTE: The transaction id identifies the payment in the gateway notifications.
        def transaction_id
          payment.provider_payment_id.presence || payment.id
        end

        def transaction_url
          "#{payment_provider.api_url}/order/#{payable.id}/transaction/#{transaction_id}"
        end

        def create_transaction
          response = LagoHttpClient::Client.new(transaction_url).put_with_response(charge_payload, payment_provider.api_headers)
          JSON.parse(response.body)
        end

        # NOTE: Returns nil when the gateway does not know the transaction, so it can be created.
        def fetch_transaction
          transaction = LagoHttpClient::Client.new(transaction_url).get(headers: payment_provider.api_headers)
          transaction.presence if transaction["result"].present?
        rescue LagoHttpClient::HttpError => e
          raise if server_error?(e)

          nil
        end

        def server_error?(error)
          error.error_code.to_i >= 500
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
              reference: payable_reference,
              description: reference
            },
            transaction: {
              reference: payable_reference,
              source: "MERCHANT"
            }
          }
        end

        # NOTE: The gateway order of a payment is its payable (invoice or payment request).
        #       An invoice is referenced by its number, unless it gates a subscription
        #       and its number is not final yet.
        def payable_reference
          if payable.is_a?(Invoice) && !payable.subscription_gated?
            payable.number
          else
            payable.id
          end
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
