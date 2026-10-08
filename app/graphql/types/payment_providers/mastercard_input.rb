# frozen_string_literal: true

module Types
  module PaymentProviders
    class MastercardInput < BaseInputObject
      description "Mastercard input arguments"

      argument :api_password, String, required: true
      argument :code, String, required: true
      argument :merchant_id, String, required: true
      argument :name, String, required: true
      argument :region, String, required: true
      argument :test_mode, Boolean, required: false
      argument :webhook_secret, String, required: false
    end
  end
end
