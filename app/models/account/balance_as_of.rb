class Account::BalanceAsOf
  FAR_FUTURE_DATE = Date.new(9999, 12, 31)

  def initialize(account, date: Date.current)
    @account = account
    @date = date.to_date
  end

  def balance
    balance_on_or_before_date&.end_balance || balance_from_latest_valuation || balance_from_cached_balance
  end

  private
    attr_reader :account, :date

    def balance_on_or_before_date
      @balance_on_or_before_date ||= account.balances
                                           .where(currency: account.currency)
                                           .where("date <= ?", date)
                                           .order(date: :desc)
                                           .first
    end

    def balance_from_latest_valuation
      return unless latest_valuation

      latest_valuation.amount + transaction_effect(after: latest_valuation.date, through: date)
    end

    def latest_valuation
      @latest_valuation ||= account.entries
                                  .where(entryable_type: "Valuation")
                                  .where("date <= ?", date)
                                  .order(date: :desc)
                                  .first
    end

    def balance_from_cached_balance
      latest_balance_amount = latest_balance&.end_balance || account.balance
      through = latest_balance&.date || FAR_FUTURE_DATE

      latest_balance_amount - transaction_effect(after: date, through: through)
    end

    def latest_balance
      @latest_balance ||= account.balances
                                .where(currency: account.currency)
                                .order(date: :desc)
                                .first
    end

    def transaction_effect(after:, through:)
      return 0.to_d if through <= after

      account.entries
             .excluding_split_parents
             .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
             .where(currency: account.currency)
             .where(date: (after + 1.day)..through)
             .sum { |entry| transaction_entry_effect(entry) }
    end

    def transaction_entry_effect(entry)
      amount = entry.amount.to_d

      account.asset? || !account.liability? ? -amount : amount
    end
end
