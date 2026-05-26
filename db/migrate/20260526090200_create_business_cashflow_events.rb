class CreateBusinessCashflowEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :business_cashflow_events, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, foreign_key: true, type: :uuid
      t.references :tax_period,
                   foreign_key: { to_table: :business_cashflow_tax_periods },
                   type: :uuid
      t.string :kind, null: false
      t.string :status, null: false, default: "planned"
      t.string :name, null: false
      t.string :counterparty
      t.bigint :amount_cents, null: false, default: 0
      t.string :direction, null: false
      t.string :currency, null: false, default: "EUR"
      t.date :event_date, null: false
      t.date :payment_date
      t.bigint :vat_amount_cents, null: false, default: 0
      t.string :vat_direction, null: false, default: "none"
      t.bigint :net_amount_cents
      t.decimal :vat_rate, precision: 5, scale: 2
      t.boolean :vat_manual, null: false, default: false
      t.string :category
      t.string :recurrence_rule
      t.string :source, null: false, default: "manual"
      t.references :linked_transaction, foreign_key: { to_table: :transactions }, type: :uuid
      t.text :notes

      t.timestamps
    end

    add_index :business_cashflow_events, [ :family_id, :event_date ]
    add_index :business_cashflow_events, [ :family_id, :status ]
    add_index :business_cashflow_events, [ :family_id, :kind ]
    add_index :business_cashflow_events, :currency
  end
end
