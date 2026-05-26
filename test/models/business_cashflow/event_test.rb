require "test_helper"

module BusinessCashflow
  class EventTest < ActiveSupport::TestCase
    test "income defaults to inflow VAT debit and net amount" do
      event = BusinessCashflow::Event.new(
        family: families(:dylan_family),
        kind: "income",
        status: "received",
        name: "Client invoice",
        amount_cents: 444_000,
        vat_amount_cents: 44_000,
        event_date: Date.new(2026, 6, 20)
      )

      assert event.valid?
      assert_equal "inflow", event.direction
      assert_equal "debit", event.vat_direction
      assert_equal 400_000, event.net_amount_cents
      assert_equal 444_000, event.bank_effect_cents
      assert_equal 400_000, event.spendable_income_effect_cents
    end

    test "expense defaults to outflow VAT credit" do
      event = BusinessCashflow::Event.new(
        family: families(:dylan_family),
        kind: "expense",
        status: "committed",
        name: "Supplier bill",
        amount_cents: 122_000,
        vat_amount_cents: 22_000,
        event_date: Date.new(2026, 6, 5)
      )

      assert event.valid?
      assert_equal "outflow", event.direction
      assert_equal "credit", event.vat_direction
      assert_equal(-122_000, event.bank_effect_cents)
    end
  end
end
