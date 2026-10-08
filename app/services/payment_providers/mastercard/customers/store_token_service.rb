# frozen_string_literal: true

module PaymentProviders
  module Mastercard
    module Customers
      # Stores a card tokenized outside of Lago (e.g. by a merchant-hosted checkout using the
      # gateway hosted session) as the default payment method of a Mastercard customer.
      #
      # The `agreement_id` is the credential-on-file agreement established by the
      # cardholder-initiated transaction that saved the card. It is replayed on every
      # merchant-initiated charge.
      class StoreTokenService < BaseService
        Result = BaseResult[:mastercard_customer, :payment_method]

        CARD_DETAILS_KEYS = %i[last4 brand expiration_month expiration_year card_holder_name].freeze

        def initialize(mastercard_customer:, token:, agreement_id: nil, card_details: {})
          @mastercard_customer = mastercard_customer
          @token = token
          @agreement_id = agreement_id
          @card_details = (card_details || {}).to_h.symbolize_keys.slice(*CARD_DETAILS_KEYS).compact_blank

          super
        end

        def call
          return result.not_found_failure!(resource: "mastercard_customer") unless mastercard_customer
          return result.single_validation_failure!(field: :token, error_code: "value_is_mandatory") if token.blank?

          ActiveRecord::Base.transaction do
            if agreement_id.present?
              mastercard_customer.agreement_id = agreement_id
              mastercard_customer.save!
            end

            result.payment_method = store_payment_method
          end

          result.mastercard_customer = mastercard_customer
          result
        rescue ActiveRecord::RecordInvalid => e
          result.record_validation_failure!(record: e.record)
        rescue BaseService::FailedResult => e
          result.fail_with_error!(e)
        end

        private

        attr_reader :mastercard_customer, :token, :agreement_id, :card_details

        def store_payment_method
          payment_method = PaymentMethods::FindOrCreateFromProviderService.call!(
            customer: mastercard_customer.customer,
            payment_provider_customer: mastercard_customer,
            provider_method_id: token,
            params: {details:},
            set_as_default: true
          ).payment_method

          # NOTE: Details are only applied when the payment method is created,
          #       storing the same token again must refresh them.
          if details.present? && payment_method.details != details.deep_stringify_keys
            payment_method.update!(details:)
          end

          payment_method
        end

        def details
          return {} if card_details.blank?

          @details ||= PaymentMethods::CardDetails.new(
            type: "card",
            last4: card_details[:last4],
            brand: card_details[:brand],
            expiration_month: card_details[:expiration_month]&.to_i,
            expiration_year: card_details[:expiration_year]&.to_i,
            card_holder_name: card_details[:card_holder_name],
            issuer: nil
          ).to_h
        end
      end
    end
  end
end
