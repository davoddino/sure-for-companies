class BusinessCashflowsController < ApplicationController
  HORIZON_OPTIONS = [ 30, 60, 90, 180, 365 ].freeze

  def show
    @settings = BusinessCashflow::Setting.for_family(Current.family)
    @horizon_days = selected_horizon_days
    @horizon_options = (HORIZON_OPTIONS + [ @horizon_days ]).uniq.sort
    BusinessCashflow::TaxPeriod.generate_quarterly_defaults!(Current.family) if Current.family.business_cashflow_tax_periods.none?

    @projection = BusinessCashflow::ProjectionService.new(Current.family, settings: @settings, horizon_days: @horizon_days).call
    @events = Current.family.business_cashflow_events.active.chronological.limit(25)
    @tax_periods = Current.family.business_cashflow_tax_periods.vat.chronological.limit(8)
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("breadcrumbs.business_cashflow"), nil ] ]
  end

  private
    def selected_horizon_days
      requested_days = params[:horizon_days].to_i
      return requested_days if HORIZON_OPTIONS.include?(requested_days)

      @settings.planning_horizon_days
    end
end
