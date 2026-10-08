# frozen_string_literal: true

module Types
  module PaymentProviders
    class Mastercard < Types::BaseObject
      graphql_name "MastercardProvider"

      field :api_password, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :code, String, null: false
      field :id, ID, null: false
      field :merchant_id, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :name, String, null: false
      field :region, String, null: true, permission: "organization:integrations:view"
      field :test_mode, Boolean, null: true, method: :test_mode?, permission: "organization:integrations:view"
      field :webhook_secret, String, null: true, permission: "organization:integrations:view"
    end
  end
end
