module BusinessCashflowsHelper
  def business_cashflow_money(cents, currency:)
    business_cashflow_money_from_cents(cents, currency:).format
  end

  def business_cashflow_signed_money(cents, currency:)
    amount = business_cashflow_money(cents.abs, currency:)
    cents.to_i.negative? ? "-#{amount}" : amount
  end

  def business_cashflow_effect_class(cents)
    cents.to_i.negative? ? "text-destructive" : "text-success"
  end

  def business_cashflow_free_cash_series(projection)
    points = [
      {
        date: projection.as_of,
        value: business_cashflow_money_from_cents(projection.free_cash_cents, currency: projection.currency)
      }
    ]

    projection.timeline.each do |item|
      points << {
        date: item.date,
        value: business_cashflow_money_from_cents(item.running_free_cash_cents, currency: projection.currency)
      }
    end

    points_by_date = points.each_with_object({}) { |point, memo| memo[point[:date]] = point }
    last_point = points_by_date.values.max_by { |point| point[:date] }

    if last_point[:date] < projection.horizon_date
      points_by_date[projection.horizon_date] = {
        date: projection.horizon_date,
        value: last_point[:value]
      }
    end

    Series.from_raw_values(points_by_date.values, interval: "1 day")
  end

  def business_cashflow_money_from_cents(cents, currency:)
    Money.new(BigDecimal(cents.to_s) / 100, currency)
  end
end
