module BusinessCashflow
  class Setting < ApplicationRecord
    self.table_name = "business_cashflow_settings"

    VAT_REGIMES = %w[quarterly monthly].freeze

    belongs_to :family

    validates :family, presence: true
    validates :vat_regime, presence: true, inclusion: { in: VAT_REGIMES }
    validates :planning_horizon_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 730 }
    validates :default_vat_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validates :country, :currency, presence: true
    validates :family_id, uniqueness: true

    before_validation :apply_family_defaults

    def self.for_family(family)
      find_or_create_by!(family:)
    end

    private
      def apply_family_defaults
        self.currency = currency.presence || "EUR"
        self.country = country.presence || "IT"
      end
  end
end
