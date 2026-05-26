class CreateBusinessCashflowSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :business_cashflow_settings, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :vat_regime, null: false, default: "quarterly"
      t.boolean :include_confirmed_income_in_free_cash, null: false, default: false
      t.boolean :include_planned_outflows_in_free_cash, null: false, default: false
      t.integer :planning_horizon_days, null: false, default: 90
      t.decimal :default_vat_rate, precision: 5, scale: 2, null: false, default: 22.0
      t.string :country, null: false, default: "IT"
      t.string :currency, null: false, default: "EUR"

      t.timestamps
    end

    add_index :business_cashflow_settings, :family_id, unique: true
  end
end
