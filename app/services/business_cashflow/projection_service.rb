module BusinessCashflow
  class ProjectionService
    Result = Struct.new(
      :as_of,
      :currency,
      :horizon_date,
      :bank_balance_cents,
      :vat_reserve_cents,
      :tax_reserve_cents,
      :committed_outflows_cents,
      :confirmed_inflows_cents,
      :free_cash_cents,
      :projected_bank_balance_cents,
      :projected_free_cash_cents,
      :lowest_projected_bank_balance_cents,
      :lowest_projected_free_cash_cents,
      :next_tax_deadline,
      :timeline,
      keyword_init: true
    )

    TimelineItem = Struct.new(
      :event,
      :date,
      :bank_effect_cents,
      :spendable_effect_cents,
      :running_bank_balance_cents,
      :running_free_cash_cents,
      :vat_reserve_cents,
      keyword_init: true
    )

    def initialize(family, as_of: Date.current, settings: nil, horizon_days: nil, starting_bank_balance_cents: nil)
      @family = family
      @as_of = as_of
      @settings = settings || BusinessCashflow::Setting.for_family(family)
      @horizon_days = horizon_days || @settings.planning_horizon_days
      @starting_bank_balance_cents = starting_bank_balance_cents
    end

    def call
      current_bank_balance = bank_balance_cents
      current_vat_reserve = vat_reserve_cents(as_of: @as_of)
      current_tax_reserve = tax_reserve_cents(as_of: @as_of)
      current_committed_outflows = committed_outflows_cents(after: @as_of, through: horizon_date)
      current_confirmed_inflows = confirmed_inflows_cents(after: @as_of, through: horizon_date)
      current_free_cash = current_bank_balance - current_vat_reserve - current_tax_reserve - current_committed_outflows
      current_free_cash += current_confirmed_inflows if @settings.include_confirmed_income_in_free_cash?

      timeline = build_timeline(
        bank_balance_cents: current_bank_balance,
        vat_reserve_cents: current_vat_reserve,
        tax_reserve_cents: current_tax_reserve,
        committed_outflows_cents: current_committed_outflows,
        confirmed_inflows_cents: current_confirmed_inflows
      )

      Result.new(
        as_of: @as_of,
        currency: @settings.currency,
        horizon_date: horizon_date,
        bank_balance_cents: current_bank_balance,
        vat_reserve_cents: current_vat_reserve,
        tax_reserve_cents: current_tax_reserve,
        committed_outflows_cents: current_committed_outflows,
        confirmed_inflows_cents: current_confirmed_inflows,
        free_cash_cents: current_free_cash,
        projected_bank_balance_cents: timeline.last&.running_bank_balance_cents || current_bank_balance,
        projected_free_cash_cents: timeline.last&.running_free_cash_cents || current_free_cash,
        lowest_projected_bank_balance_cents: ([ current_bank_balance ] + timeline.map(&:running_bank_balance_cents)).min,
        lowest_projected_free_cash_cents: ([ current_free_cash ] + timeline.map(&:running_free_cash_cents)).min,
        next_tax_deadline: next_tax_deadline,
        timeline: timeline
      )
    end

    private
      attr_reader :horizon_days

      def horizon_date
        @horizon_date ||= @as_of + horizon_days.days
      end

      def events
        @events ||= @family.business_cashflow_events.active.where(currency: @settings.currency)
      end

      def bank_balance_cents
        baseline = @starting_bank_balance_cents || account_balance_cents
        baseline + actual_manual_event_effects_cents
      end

      def account_balance_cents
        @family.accounts
               .visible
               .where(currency: @settings.currency, accountable_type: "Depository")
               .sum(:balance)
               .to_d
               .then { |amount| (amount * 100).round }
      end

      def actual_manual_event_effects_cents
        events.where(status: BusinessCashflow::Event::ACTUAL_STATUSES)
              .where("event_date <= ?", @as_of)
              .where(linked_transaction_id: nil)
              .sum { |event| event.bank_effect_cents }
      end

      def vat_reserve_cents(as_of:)
        debit = events.where(kind: "income", vat_direction: "debit")
                      .where(status: %w[confirmed received late])
                      .where("event_date <= ?", as_of)
                      .sum(:vat_amount_cents)

        credit = events.where(kind: "expense", vat_direction: "credit")
                       .where(status: %w[committed paid])
                       .where("event_date <= ?", as_of)
                       .sum(:vat_amount_cents)

        paid = events.where(kind: "tax_payment")
                     .where(status: "paid")
                     .where("event_date <= ?", as_of)
                     .sum(:amount_cents)

        [ debit - credit - paid, 0 ].max
      end

      def tax_reserve_cents(as_of:)
        events.where(kind: "reserve_adjustment")
              .where(status: %w[planned committed confirmed])
              .where("event_date <= ?", as_of)
              .sum(:amount_cents)
      end

      def committed_outflows_cents(after:, through:)
        statuses = [ "committed" ]
        statuses << "planned" if @settings.include_planned_outflows_in_free_cash?

        events.where(direction: "outflow", status: statuses)
              .where(event_date: (after + 1.day)..through)
              .where.not(kind: %w[tax_payment reserve_adjustment])
              .sum(:amount_cents)
      end

      def confirmed_inflows_cents(after:, through:)
        events.where(direction: "inflow", status: "confirmed")
              .where(event_date: (after + 1.day)..through)
              .sum(:amount_cents)
      end

      def forecast_events
        included_statuses = %w[planned committed confirmed expected late]
        included_statuses << "paid"
        included_statuses << "received"

        events.where(status: included_statuses)
              .where(event_date: (@as_of + 1.day)..horizon_date)
              .chronological
      end

      def build_timeline(bank_balance_cents:, vat_reserve_cents:, tax_reserve_cents:, committed_outflows_cents:, confirmed_inflows_cents:)
        running_bank = bank_balance_cents
        running_vat_reserve = vat_reserve_cents
        previous_free_cash = bank_balance_cents - vat_reserve_cents - tax_reserve_cents - committed_outflows_cents
        previous_free_cash += confirmed_inflows_cents if @settings.include_confirmed_income_in_free_cash?

        forecast_events.to_a.map do |event|
          bank_effect = forecast_bank_effect_for(event)
          running_bank += bank_effect
          running_vat_reserve = forecast_vat_reserve_after(running_vat_reserve, event)

          future_committed = committed_outflows_cents(after: event.event_date, through: horizon_date)
          future_confirmed = confirmed_inflows_cents(after: event.event_date, through: horizon_date)
          running_free = running_bank - running_vat_reserve - tax_reserve_cents - future_committed
          running_free += future_confirmed if @settings.include_confirmed_income_in_free_cash?

          item = TimelineItem.new(
            event: event,
            date: event.event_date,
            bank_effect_cents: bank_effect,
            spendable_effect_cents: running_free - previous_free_cash,
            running_bank_balance_cents: running_bank,
            running_free_cash_cents: running_free,
            vat_reserve_cents: running_vat_reserve
          )
          previous_free_cash = item.running_free_cash_cents
          item
        end
      end

      def forecast_bank_effect_for(event)
        case event.status
        when "expected"
          0
        else
          event.bank_effect_cents
        end
      end

      def forecast_vat_reserve_after(current_reserve, event)
        case event.kind
        when "income"
          event.vat_direction == "debit" && %w[confirmed received late].include?(event.status) ? current_reserve + event.vat_amount_cents : current_reserve
        when "expense"
          event.vat_direction == "credit" && %w[committed paid].include?(event.status) ? [ current_reserve - event.vat_amount_cents, 0 ].max : current_reserve
        when "tax_payment"
          [ current_reserve - event.amount_cents, 0 ].max
        else
          current_reserve
        end
      end

      def next_tax_deadline
        @family.business_cashflow_tax_periods
               .vat
               .open_or_reviewed
               .where("due_date >= ?", @as_of)
               .order(:due_date)
               .first
      end
  end
end
