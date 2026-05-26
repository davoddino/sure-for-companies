require "test_helper"

module BusinessCashflow
  class SettingTest < ActiveSupport::TestCase
    test "creates one settings row per family with conservative defaults" do
      family = families(:dylan_family)
      family.update!(currency: "EUR", country: "IT")

      setting = BusinessCashflow::Setting.for_family(family)

      assert_equal "quarterly", setting.vat_regime
      assert_equal false, setting.include_confirmed_income_in_free_cash
      assert_equal false, setting.include_planned_outflows_in_free_cash
      assert_equal 90, setting.planning_horizon_days
      assert_equal BigDecimal("22.0"), setting.default_vat_rate
      assert_equal "IT", setting.country
      assert_equal "EUR", setting.currency
      assert_equal setting, BusinessCashflow::Setting.for_family(family)
    end
  end
end
