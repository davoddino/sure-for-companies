module BusinessCashflow
  class Event < ApplicationRecord
    self.table_name = "business_cashflow_events"

    KINDS = %w[income expense tax_payment reserve_adjustment transfer].freeze
    STATUSES = %w[draft planned committed confirmed paid cancelled late expected received].freeze
    DIRECTIONS = %w[inflow outflow].freeze
    VAT_DIRECTIONS = %w[debit credit none].freeze
    SOURCES = %w[manual imported generated linked_transaction].freeze

    ACTUAL_STATUSES = %w[paid received].freeze
    IGNORED_STATUSES = %w[draft cancelled].freeze

    belongs_to :family
    belongs_to :account, optional: true
    belongs_to :tax_period,
               class_name: "BusinessCashflow::TaxPeriod",
               optional: true,
               inverse_of: :events
    belongs_to :linked_transaction, class_name: "Transaction", optional: true

    before_validation :apply_defaults

    validates :family, :kind, :status, :name, :amount_cents, :direction, :currency, :event_date, :vat_amount_cents, :vat_direction, :source, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :status, inclusion: { in: STATUSES }
    validates :direction, inclusion: { in: DIRECTIONS }
    validates :vat_direction, inclusion: { in: VAT_DIRECTIONS }
    validates :source, inclusion: { in: SOURCES }
    validates :amount_cents, :vat_amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :net_amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :vat_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
    validate :account_belongs_to_family
    validate :tax_period_belongs_to_family
    validate :vat_amount_cannot_exceed_amount

    scope :active, -> { where.not(status: IGNORED_STATUSES) }
    scope :chronological, -> { order(:event_date, :created_at) }
    scope :within, ->(range) { where(event_date: range) }

    def actual?
      ACTUAL_STATUSES.include?(status)
    end

    def ignored?
      IGNORED_STATUSES.include?(status)
    end

    def outflow?
      direction == "outflow"
    end

    def inflow?
      direction == "inflow"
    end

    def bank_effect_cents
      inflow? ? amount_cents : -amount_cents
    end

    def spendable_income_effect_cents
      return 0 unless kind == "income"

      amount_cents - vat_amount_cents
    end

    def reserve_settlement?
      kind == "tax_payment"
    end

    private
      def apply_defaults
        self.direction = default_direction if direction.blank?
        self.currency = currency.presence || family&.business_cashflow_setting&.currency.presence || "EUR"
        self.vat_direction = default_vat_direction if vat_direction.blank? || default_vat_direction_required?
        self.net_amount_cents = [ amount_cents.to_i - vat_amount_cents.to_i, 0 ].max if net_amount_cents.blank?
      end

      def default_direction
        case kind
        when "income" then "inflow"
        else "outflow"
        end
      end

      def default_vat_direction
        case kind
        when "income" then "debit"
        when "expense" then "credit"
        else "none"
        end
      end

      def default_vat_direction_required?
        vat_direction == "none" && vat_amount_cents.to_i.positive? && %w[income expense].include?(kind)
      end

      def account_belongs_to_family
        return if account.blank? || family.blank?

        errors.add(:account, "must belong to the same family") if account.family_id != family_id
      end

      def tax_period_belongs_to_family
        return if tax_period.blank? || family.blank?

        errors.add(:tax_period, "must belong to the same family") if tax_period.family_id != family_id
      end

      def vat_amount_cannot_exceed_amount
        return if vat_amount_cents.blank? || amount_cents.blank?

        errors.add(:vat_amount_cents, "cannot exceed amount") if vat_amount_cents > amount_cents
      end
  end
end
