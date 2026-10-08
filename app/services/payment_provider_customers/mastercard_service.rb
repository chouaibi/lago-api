# frozen_string_literal: true

module PaymentProviderCustomers
  class MastercardService < BaseService
    include Customers::PaymentProviderFinder
    include TypedResults

    RESULTS = {
      create: BaseResult[:mastercard_customer],
      update: BaseResult,
      generate_checkout_url: BaseResult
    }.freeze

    private

    # NOTE: The gateway has no customer object: the card is tokenized outside of Lago
    #       and stored with PaymentProviders::Mastercard::Customers::StoreTokenService.
    def create(mastercard_customer)
      @mastercard_customer = mastercard_customer
      result.mastercard_customer = mastercard_customer
      result
    end

    def update(mastercard_customer)
      @mastercard_customer = mastercard_customer
      result
    end

    def generate_checkout_url(mastercard_customer, send_webhook: true)
      @mastercard_customer = mastercard_customer
      result.not_allowed_failure!(code: "feature_not_supported")
    end

    attr_accessor :mastercard_customer

    delegate :customer, to: :mastercard_customer
  end
end
