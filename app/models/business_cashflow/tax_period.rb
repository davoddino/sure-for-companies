module BusinessCashflow
  class TaxPeriod < ApplicationRecord
    self.table_name = "business_cashflow_tax_periods"

    KINDS = %w[vat].freeze
    PERIOD_TYPES = %w[monthly quarterly].freeze
    STATUSES = %w[open reviewed closed paid].freeze
    QUARTERLY_DUE_DATES = {
      1 => [ 5, 16, 0 ],
      2 => [ 8, 20, 0 ],
      3 => [ 11, 16, 0 ],
      4 => [ 3, 16, 1 ]
    }.freeze

    belongs_to :family
    has_many :events,
             class_name: "BusinessCashflow::Event",
             foreign_key: :tax_period_id,
             dependent: :nullify,
             inverse_of: :tax_period

    validates :family, :kind, :period_type, :period_key, :year, :start_date, :end_date, :due_date, :status, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :period_type, inclusion: { in: PERIOD_TYPES }
    validates :status, inclusion: { in: STATUSES }
    validates :quarter, inclusion: { in: 1..4 }, allow_nil: true
    validates :month, inclusion: { in: 1..12 }, allow_nil: true
    validates :vat_debit_cents, :vat_credit_cents, :vat_due_cents, :manual_adjustment_cents,
              numericality: { only_integer: true }
    validates :period_key, uniqueness: { scope: [ :family_id, :kind, :period_type ] }
    validate :dates_are_ordered

    scope :vat, -> { where(kind: "vat") }
    scope :open_or_reviewed, -> { where(status: %w[open reviewed]) }
    scope :chronological, -> { order(:start_date, :period_key) }

    def self.generate_quarterly_defaults!(family, years: [ Date.current.year, Date.current.year + 1 ])
      Array(years).flat_map do |year|
        (1..4).map { |quarter| find_or_create_quarterly_vat_period!(family, year:, quarter:) }
      end
    end

    def self.find_or_create_quarterly_vat_period!(family, year:, quarter:)
      find_or_create_by!(
        family: family,
        kind: "vat",
        period_type: "quarterly",
        period_key: "#{year}-Q#{quarter}"
      ) do |period|
        period.year = year
        period.quarter = quarter
        period.start_date = Date.new(year, ((quarter - 1) * 3) + 1, 1)
        period.end_date = period.start_date.end_of_quarter
        period.due_date = quarterly_due_date(year, quarter)
      end
    end

    def self.quarterly_due_date(year, quarter)
      month, day, year_offset = QUARTERLY_DUE_DATES.fetch(quarter)
      Date.new(year + year_offset, month, day)
    end

    def estimated_vat_due_cents
      [ vat_debit_cents - vat_credit_cents + manual_adjustment_cents, 0 ].max
    end

    def estimated_vat_credit_cents
      [ vat_credit_cents - vat_debit_cents - manual_adjustment_cents, 0 ].max
    end

    private
      def dates_are_ordered
        return if start_date.blank? || end_date.blank?

        errors.add(:end_date, "must be on or after start date") if end_date < start_date
      end
  end
end
