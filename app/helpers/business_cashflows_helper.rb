module BusinessCashflowsHelper
  def business_cashflow_money(cents, currency:)
    Money.new(BigDecimal(cents.to_s) / 100, currency).format
  end

  def business_cashflow_signed_money(cents, currency:)
    amount = business_cashflow_money(cents.abs, currency:)
    cents.to_i.negative? ? "-#{amount}" : amount
  end

  def business_cashflow_effect_class(cents)
    cents.to_i.negative? ? "text-destructive" : "text-success"
  end
end
