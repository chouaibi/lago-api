# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentProviders::MastercardInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:api_password).of_type("String!")
    expect(subject).to accept_argument(:code).of_type("String!")
    expect(subject).to accept_argument(:merchant_id).of_type("String!")
    expect(subject).to accept_argument(:name).of_type("String!")
    expect(subject).to accept_argument(:region).of_type("String!")
    expect(subject).to accept_argument(:test_mode).of_type("Boolean")
    expect(subject).to accept_argument(:webhook_secret).of_type("String")
  end
end
