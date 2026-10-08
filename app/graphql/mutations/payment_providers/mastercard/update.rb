# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Mastercard
      class Update < Base
        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateMastercardPaymentProvider"
        description "Update Mastercard payment provider"

        input_object_class Types::PaymentProviders::UpdateMastercardInput

        type Types::PaymentProviders::Mastercard
      end
    end
  end
end
