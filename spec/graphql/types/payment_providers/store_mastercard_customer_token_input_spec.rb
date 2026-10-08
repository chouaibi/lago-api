# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::PaymentProviders::StoreMastercardCustomerTokenInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:customer_id).of_type("ID!")
    expect(subject).to accept_argument(:token).of_type("String!")
    expect(subject).to accept_argument(:agreement_id).of_type("String")
    expect(subject).to accept_argument(:brand).of_type("String")
    expect(subject).to accept_argument(:card_holder_name).of_type("String")
    expect(subject).to accept_argument(:expiration_month).of_type("Int")
    expect(subject).to accept_argument(:expiration_year).of_type("Int")
    expect(subject).to accept_argument(:last4).of_type("String")
  end
end
