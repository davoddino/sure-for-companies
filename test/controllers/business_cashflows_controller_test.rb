require "test_helper"

class BusinessCashflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ensure_tailwind_build
    sign_in @user = users(:family_admin)
    @family = @user.family
    @family.update!(currency: "EUR", country: "IT")
    @family.business_cashflow_events.destroy_all
    @family.business_cashflow_tax_periods.destroy_all
    @family.business_cashflow_setting&.destroy!
  end

  test "show renders business cashflow dashboard" do
    @family.business_cashflow_events.create!(
      kind: "income",
      status: "received",
      name: "Client invoice",
      amount_cents: 444_000,
      vat_amount_cents: 44_000,
      event_date: Date.current
    )

    get business_cashflow_path

    assert_response :ok
    assert_select "h1", text: "Business Cashflow"
    assert_select "p", text: "Disponibilita libera"
    assert_equal 8, @family.business_cashflow_tax_periods.count
  end
end
