# frozen_string_literal: true

module Api
  module V1
    module Customers
      class MastercardTokensController < BaseController
        def create
          mastercard_customer = customer.mastercard_customer
          return not_found_error(resource: "mastercard_customer") unless mastercard_customer

          result = ::PaymentProviders::Mastercard::Customers::StoreTokenService.call(
            mastercard_customer:,
            token: token_params[:token],
            agreement_id: token_params[:agreement_id],
            card_details: token_params.except(:token, :agreement_id).to_h
          )

          if result.success?
            render_customer(result.mastercard_customer.customer)
          else
            render_error_response(result)
          end
        end

        private

        def resource_name
          "payment_method"
        end

        def token_params
          @token_params ||= params.require(:mastercard_token).permit(
            :token,
            :agreement_id,
            :last4,
            :brand,
            :expiration_month,
            :expiration_year,
            :card_holder_name
          )
        end

        def render_customer(customer)
          render(
            json: ::V1::CustomerSerializer.new(
              customer,
              root_name: "customer",
              includes: %i[taxes integration_customers applicable_invoice_custom_sections error_details]
            )
          )
        end
      end
    end
  end
end
