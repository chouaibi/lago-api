# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Mastercard
      class Create < Base
        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "AddMastercardPaymentProvider"
        description "Add Mastercard payment provider"

        input_object_class Types::PaymentProviders::MastercardInput

        type Types::PaymentProviders::Mastercard
      end
    end
  end
end
