# CavadaLabs Cashflow

This fork adds a `BusinessCashflow` Rails namespace for internal CavadaLabs small-business cash planning.

The first implementation phase covers:

- CavadaLabs-branded product defaults via `PRODUCT_NAME` and `BRAND_NAME`.
- `BusinessCashflow::Setting` for conservative planning defaults.
- `BusinessCashflow::Event` for incomes, expenses, tax payments, reserves, and transfers.
- `BusinessCashflow::TaxPeriod` with editable Italian quarterly VAT planning defaults.
- `BusinessCashflow::ProjectionService` for bank balance, VAT reserve, committed outflows, confirmed inflows, free cash, and forecast timeline calculations.

Money is stored as integer cents in the business cashflow tables. The module is a planning tool, not fiscal compliance software. VAT deadlines and amounts are estimates and should be verified with a commercialista.

Core acceptance scenario:

- Starting bank balance: 10,000 EUR.
- Received client income: 4,440 EUR gross, 440 EUR VAT.
- Committed future expense: 1,000 EUR.
- Before VAT/F24 payment: bank balance is 14,440 EUR and free cash is 13,000 EUR.
- After paying the 440 EUR VAT/F24 reserve: bank balance is 14,000 EUR and free cash remains 13,000 EUR, avoiding double subtraction.
