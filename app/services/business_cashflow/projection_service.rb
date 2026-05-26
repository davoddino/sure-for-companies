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

    ForecastTransactionEvent = Struct.new(
      :entry,
      :kind,
      :status,
      :name,
      :amount_cents,
      :vat_amount_cents,
      :vat_direction,
      :event_date,
      :bank_effect_cents,
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

      def bank_accounts
        @bank_accounts ||= @family.accounts
                                  .visible
                                  .where(currency: @settings.currency, accountable_type: "Depository")
      end

      def bank_balance_cents
        baseline = @starting_bank_balance_cents || account_balance_cents
        baseline + actual_manual_event_effects_cents
      end

      def account_balance_cents
        bank_accounts.sum { |account| account_balance_as_of_cents(account) }
      end

      def account_balance_as_of_cents(account)
        latest_balance = account.balances
                                .where(currency: @settings.currency)
                                .order(date: :desc)
                                .first

        latest_balance_cents = money_to_cents(latest_balance&.end_balance || account.balance)
        latest_balance_cents - future_account_entry_effect_cents(account, through: latest_balance&.date)
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

        event_outflows = events.where(direction: "outflow", status: statuses)
                               .where(event_date: (after + 1.day)..through)
                               .where.not(kind: %w[tax_payment reserve_adjustment])
                               .sum(:amount_cents)

        event_outflows + future_transaction_outflows_cents(after:, through:)
      end

      def confirmed_inflows_cents(after:, through:)
        event_inflows = events.where(direction: "inflow", status: "confirmed")
                              .where(event_date: (after + 1.day)..through)
                              .sum(:amount_cents)

        event_inflows + future_transaction_inflows_cents(after:, through:)
      end

      def forecast_events
        included_statuses = %w[planned committed confirmed expected late]
        included_statuses << "paid"
        included_statuses << "received"

        business_events = events.where(status: included_statuses)
                                .where(event_date: (@as_of + 1.day)..horizon_date)
                                .to_a

        (business_events + future_transaction_forecast_events(after: @as_of, through: horizon_date))
          .sort_by { |event| [ event.event_date, event.name.to_s ] }
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

      def future_transaction_outflows_cents(after:, through:)
        future_transaction_entries(after:, through:)
          .sum { |entry| [ -entry_bank_effect_cents(entry), 0 ].max }
      end

      def future_transaction_inflows_cents(after:, through:)
        future_transaction_entries(after:, through:)
          .sum { |entry| [ entry_bank_effect_cents(entry), 0 ].max }
      end

      def future_transaction_forecast_events(after:, through:)
        future_transaction_entries(after:, through:).map do |entry|
          bank_effect_cents = entry_bank_effect_cents(entry)

          ForecastTransactionEvent.new(
            entry: entry,
            kind: "transaction",
            status: bank_effect_cents.negative? ? "committed" : "confirmed",
            name: entry.name,
            amount_cents: bank_effect_cents.abs,
            vat_amount_cents: transaction_business_vat_cents(entry.entryable),
            vat_direction: "none",
            event_date: entry.date,
            bank_effect_cents: bank_effect_cents
          )
        end
      end

      def future_transaction_entries(after:, through:)
        @future_transaction_entries ||= {}
        @future_transaction_entries[[ after, through ]] ||= begin
          @family.entries
                 .preload(:account, :entryable)
                 .joins(:account)
                 .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
                 .where(accounts: { status: %w[draft active], currency: @settings.currency, accountable_type: "Depository" })
                 .where(entries: { currency: @settings.currency, excluded: false })
                 .where(date: (after + 1.day)..through)
                 .where.not(transactions: { kind: "funds_movement" })
                 .where.not(entryable_id: linked_business_cashflow_transaction_ids)
                 .to_a
        end
      end

      def future_account_entry_effect_cents(account, through:)
        return 0 if through.present? && through <= @as_of

        @future_account_entry_effect_cents ||= {}
        @future_account_entry_effect_cents[[ account.id, through ]] ||= begin
          entries = account.entries
                           .preload(:account)
                           .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
                           .where(currency: @settings.currency)
                           .where(date: (@as_of + 1.day)..(through || Date.new(9999, 12, 31)))

          entries.sum { |entry| entry_bank_effect_cents(entry) }
        end
      end

      def linked_business_cashflow_transaction_ids
        events.where.not(linked_transaction_id: nil).select(:linked_transaction_id)
      end

      def entry_bank_effect_cents(entry)
        amount = entry.amount.to_d
        effect = entry.account.asset? || !entry.account.liability? ? -amount : amount

        money_to_cents(effect)
      end

      def transaction_business_vat_cents(transaction)
        return 0 unless transaction.respond_to?(:business_vat_amount)

        money_to_cents(transaction.business_vat_amount.presence || 0)
      end

      def money_to_cents(amount)
        (amount.to_d * 100).round
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
