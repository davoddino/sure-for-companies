require "test_helper"

module BusinessCashflow
  class TaxPeriodTest < ActiveSupport::TestCase
    test "generates editable Italian quarterly VAT defaults" do
      family = families(:dylan_family)

      periods = BusinessCashflow::TaxPeriod.generate_quarterly_defaults!(family, years: [ 2026 ])

      assert_equal 4, periods.size
      assert_equal Date.new(2026, 5, 16), periods.find { |period| period.period_key == "2026-Q1" }.due_date
      assert_equal Date.new(2026, 8, 20), periods.find { |period| period.period_key == "2026-Q2" }.due_date
      assert_equal Date.new(2026, 11, 16), periods.find { |period| period.period_key == "2026-Q3" }.due_date
      assert_equal Date.new(2027, 3, 16), periods.find { |period| period.period_key == "2026-Q4" }.due_date
    end

    test "calculates estimated VAT due and credit" do
      period = BusinessCashflow::TaxPeriod.new(
        family: families(:dylan_family),
        period_key: "2026-Q2",
        year: 2026,
        quarter: 2,
        start_date: Date.new(2026, 4, 1),
        end_date: Date.new(2026, 6, 30),
        due_date: Date.new(2026, 8, 20),
        vat_debit_cents: 44_000,
        vat_credit_cents: 22_000
      )

      assert_equal 22_000, period.estimated_vat_due_cents
      assert_equal 0, period.estimated_vat_credit_cents
    end
  end
end
