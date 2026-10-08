# frozen_string_literal: true

module Mutations
  module PaymentProviders
    module Mastercard
      class StoreCustomerToken < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "payment_methods:create"

        graphql_name "StoreMastercardCustomerToken"
        description "Store a Mastercard card token, tokenized outside of Lago, as the default payment method of a customer"

        input_object_class Types::PaymentProviders::StoreMastercardCustomerTokenInput

        type Types::Customers::Object

        def resolve(customer_id:, token:, agreement_id: nil, **card_details)
          customer = current_organization.customers.find_by(id: customer_id)
          return not_found_error(resource: "customer") unless customer

          result = ::PaymentProviders::Mastercard::Customers::StoreTokenService.call(
            mastercard_customer: customer.mastercard_customer,
            token:,
            agreement_id:,
            card_details:
          )

          result.success? ? result.mastercard_customer.customer : result_error(result)
        end
      end
    end
  end
end
