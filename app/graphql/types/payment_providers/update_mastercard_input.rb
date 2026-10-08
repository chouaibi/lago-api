# frozen_string_literal: true

module Types
  module PaymentProviders
    class UpdateMastercardInput < BaseInputObject
      description "Update Mastercard input arguments"

      argument :id, ID, required: true

      argument :api_password, String, required: false
      argument :code, String, required: false
      argument :merchant_id, String, required: false
      argument :name, String, required: false
      argument :region, String, required: false
      argument :test_mode, Boolean, required: false
      argument :webhook_secret, String, required: false
    end
  end
end
