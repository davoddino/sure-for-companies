class CreateBusinessCashflowTaxPeriods < ActiveRecord::Migration[7.2]
  def change
    create_table :business_cashflow_tax_periods, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :kind, null: false, default: "vat"
      t.string :period_type, null: false, default: "quarterly"
      t.string :period_key, null: false
      t.integer :year, null: false
      t.integer :quarter
      t.integer :month
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.date :due_date, null: false
      t.string :status, null: false, default: "open"
      t.bigint :vat_debit_cents, null: false, default: 0
      t.bigint :vat_credit_cents, null: false, default: 0
      t.bigint :vat_due_cents, null: false, default: 0
      t.bigint :manual_adjustment_cents, null: false, default: 0
      t.text :notes

      t.timestamps
    end

    add_index :business_cashflow_tax_periods,
              [ :family_id, :kind, :period_type, :period_key ],
              unique: true,
              name: "idx_business_cashflow_tax_periods_unique_key"
    add_index :business_cashflow_tax_periods, [ :family_id, :due_date ]
    add_index :business_cashflow_tax_periods, :status
  end
end
