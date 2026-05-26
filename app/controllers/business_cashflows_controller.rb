class BusinessCashflowsController < ApplicationController
  def show
    @settings = BusinessCashflow::Setting.for_family(Current.family)
    BusinessCashflow::TaxPeriod.generate_quarterly_defaults!(Current.family) if Current.family.business_cashflow_tax_periods.none?

    @projection = BusinessCashflow::ProjectionService.new(Current.family, settings: @settings).call
    @events = Current.family.business_cashflow_events.active.chronological.limit(25)
    @tax_periods = Current.family.business_cashflow_tax_periods.vat.chronological.limit(8)
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("breadcrumbs.business_cashflow"), nil ] ]
  end
end
