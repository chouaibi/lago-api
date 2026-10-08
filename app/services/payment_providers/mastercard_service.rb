# frozen_string_literal: true

module PaymentProviders
  class MastercardService < BaseService
    Result = BaseResult[:mastercard_provider]

    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization].id,
        code: args[:code],
        id: args[:id],
        payment_provider_type: "mastercard"
      )

      mastercard_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::MastercardProvider.new(
          organization_id: args[:organization].id,
          code: args[:code]
        )
      end

      old_code = mastercard_provider.code

      mastercard_provider.merchant_id = args[:merchant_id] if args.key?(:merchant_id)
      mastercard_provider.api_password = args[:api_password] if args.key?(:api_password)
      mastercard_provider.region = args[:region] if args.key?(:region)
      mastercard_provider.test_mode = args[:test_mode] if args.key?(:test_mode)
      mastercard_provider.webhook_secret = args[:webhook_secret] if args.key?(:webhook_secret)
      mastercard_provider.code = args[:code] if args.key?(:code)
      mastercard_provider.name = args[:name] if args.key?(:name)
      mastercard_provider.save!

      if payment_provider_code_changed?(mastercard_provider, old_code, args)
        mastercard_provider.customers.update_all(payment_provider_code: args[:code]) # rubocop:disable Rails/SkipsModelValidations
      end

      result.mastercard_provider = mastercard_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
