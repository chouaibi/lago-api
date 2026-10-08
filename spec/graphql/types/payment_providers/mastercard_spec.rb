# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentProviders::Mastercard do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:merchant_id).of_type("ObfuscatedString").with_permission("organization:integrations:view")
    expect(subject).to have_field(:api_password).of_type("ObfuscatedString").with_permission("organization:integrations:view")
    expect(subject).to have_field(:region).of_type("String").with_permission("organization:integrations:view")
    expect(subject).to have_field(:test_mode).of_type("Boolean").with_permission("organization:integrations:view")
    expect(subject).to have_field(:webhook_secret).of_type("String").with_permission("organization:integrations:view")
  end
end
