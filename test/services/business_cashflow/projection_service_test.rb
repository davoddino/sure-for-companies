require "test_helper"

module BusinessCashflow
  class ProjectionServiceTest < ActiveSupport::TestCase
    setup do
      @family = families(:dylan_family)
      @family.update!(currency: "EUR", country: "IT")
      @family.business_cashflow_events.destroy_all
      @family.business_cashflow_tax_periods.destroy_all
      @family.business_cashflow_setting&.destroy!
      @setting = BusinessCashflow::Setting.for_family(@family)
      @as_of = Date.new(2026, 6, 1)
    end

    test "acceptance scenario keeps VAT payment from reducing free cash twice" do
      BusinessCashflow::Event.create!(
        family: @family,
        kind: "income",
        status: "received",
        name: "Client invoice",
        counterparty: "Client SRL",
        amount_cents: 444_000,
        vat_amount_cents: 44_000,
        event_date: @as_of
      )

      BusinessCashflow::Event.create!(
        family: @family,
        kind: "expense",
        status: "committed",
        name: "Committed supplier",
        amount_cents: 100_000,
        event_date: Date.new(2026, 6, 20)
      )

      before_payment = BusinessCashflow::ProjectionService.new(
        @family,
        as_of: @as_of,
        starting_bank_balance_cents: 1_000_000
      ).call

      assert_equal 1_444_000, before_payment.bank_balance_cents
      assert_equal 44_000, before_payment.vat_reserve_cents
      assert_equal 100_000, before_payment.committed_outflows_cents
      assert_equal 1_300_000, before_payment.free_cash_cents

      BusinessCashflow::Event.create!(
        family: @family,
        kind: "tax_payment",
        status: "paid",
        name: "F24 IVA",
        amount_cents: 44_000,
        event_date: Date.new(2026, 6, 16)
      )

      after_payment = BusinessCashflow::ProjectionService.new(
        @family,
        as_of: Date.new(2026, 6, 16),
        starting_bank_balance_cents: 1_000_000
      ).call

      assert_equal 1_400_000, after_payment.bank_balance_cents
      assert_equal 0, after_payment.vat_reserve_cents
      assert_equal 100_000, after_payment.committed_outflows_cents
      assert_equal 1_300_000, after_payment.free_cash_cents
    end

    test "confirmed future income is tracked but excluded from free cash by default" do
      BusinessCashflow::Event.create!(
        family: @family,
        kind: "income",
        status: "confirmed",
        name: "Future client invoice",
        amount_cents: 244_000,
        vat_amount_cents: 44_000,
        event_date: Date.new(2026, 6, 20)
      )

      result = BusinessCashflow::ProjectionService.new(
        @family,
        as_of: @as_of,
        starting_bank_balance_cents: 1_000_000
      ).call

      assert_equal 244_000, result.confirmed_inflows_cents
      assert_equal 1_000_000, result.free_cash_cents
    end

    test "transaction VAT and stamp duty metadata feed reserves and free cash" do
      account = @family.accounts.create!(
        name: "EUR bank",
        balance: 3220,
        currency: "EUR",
        classification: "asset",
        accountable: Depository.new
      )

      income = Transaction.new
      income.business_vat_amount = "440.00"
      income.business_stamp_duty_amount = "2.00"

      account.entries.create!(
        name: "Client invoice",
        date: @as_of,
        amount: -4440,
        currency: "EUR",
        entryable: income
      )

      expense = Transaction.new
      expense.business_vat_amount = "220.00"

      account.entries.create!(
        name: "Supplier bill",
        date: @as_of,
        amount: 1220,
        currency: "EUR",
        entryable: expense
      )

      result = BusinessCashflow::ProjectionService.new(@family, as_of: @as_of).call

      assert_equal 322_000, result.bank_balance_cents
      assert_equal 22_000, result.vat_reserve_cents
      assert_equal 200, result.tax_reserve_cents
      assert_equal 299_800, result.free_cash_cents
    end

    test "bank balance uses as-of balance while future transactions reduce free cash" do
      account = @family.accounts.create!(
        name: "EUR bank",
        balance: 900,
        currency: "EUR",
        classification: "asset",
        accountable: Depository.new
      )

      account.balances.create!(
        date: @as_of,
        balance: 1000,
        currency: "EUR",
        start_cash_balance: 1000,
        flows_factor: 1
      )

      account.entries.create!(
        name: "Future supplier payment",
        date: @as_of + 10.days,
        amount: 100,
        currency: "EUR",
        entryable: Transaction.new
      )

      account.balances.create!(
        date: @as_of + 10.days,
        balance: 900,
        currency: "EUR",
        start_cash_balance: 1000,
        cash_outflows: 100,
        flows_factor: 1
      )

      result = BusinessCashflow::ProjectionService.new(@family, as_of: @as_of).call

      assert_equal 100_000, result.bank_balance_cents
      assert_equal 10_000, result.committed_outflows_cents
      assert_equal 90_000, result.free_cash_cents
      assert_equal 90_000, result.projected_bank_balance_cents
      assert_equal "Future supplier payment", result.timeline.first.event.name
    end

    test "bank balance backs future transactions out of cached account balance" do
      account = @family.accounts.create!(
        name: "EUR bank without balances",
        balance: 900,
        currency: "EUR",
        classification: "asset",
        accountable: Depository.new
      )

      account.entries.create!(
        name: "Future supplier payment",
        date: @as_of + 10.days,
        amount: 100,
        currency: "EUR",
        entryable: Transaction.new
      )

      result = BusinessCashflow::ProjectionService.new(@family, as_of: @as_of).call

      assert_equal 100_000, result.bank_balance_cents
      assert_equal 10_000, result.committed_outflows_cents
      assert_equal 90_000, result.free_cash_cents
    end

    test "returns next open VAT deadline" do
      BusinessCashflow::TaxPeriod.generate_quarterly_defaults!(@family, years: [ 2026 ])

      result = BusinessCashflow::ProjectionService.new(
        @family,
        as_of: Date.new(2026, 6, 1),
        starting_bank_balance_cents: 1_000_000
      ).call

      assert_equal "2026-Q2", result.next_tax_deadline.period_key
      assert_equal Date.new(2026, 8, 20), result.next_tax_deadline.due_date
    end
  end
end
