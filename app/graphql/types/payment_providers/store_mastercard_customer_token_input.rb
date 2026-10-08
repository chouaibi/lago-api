# frozen_string_literal: true

module Types
  module PaymentProviders
    class StoreMastercardCustomerTokenInput < BaseInputObject
      description "Store Mastercard customer token input arguments"

      argument :agreement_id, String, required: false
      argument :brand, String, required: false
      argument :card_holder_name, String, required: false
      argument :customer_id, ID, required: true
      argument :expiration_month, Integer, required: false
      argument :expiration_year, Integer, required: false
      argument :last4, String, required: false
      argument :token, String, required: true
    end
  end
end
