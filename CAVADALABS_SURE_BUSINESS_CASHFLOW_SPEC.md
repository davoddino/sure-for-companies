# CavadaLabs Cashflow - Sure Fork Implementation Spec

Version: 0.1
Owner: CavadaLabs
Target repo: fork of Sure / Maybe-derived finance app
Primary user: CavadaLabs internal use
Scope: personal/internal business cashflow planning for an Italian SRL or small business

---

## 1. Executive summary

This fork should turn Sure into a CavadaLabs-branded business cashflow planner.

The goal is not accounting, invoicing, SDI, double-entry bookkeeping, tax filing, or replacing the commercialista.

The goal is to answer one practical question every day:

> How much money is really available to spend, after subtracting VAT, F24, tax reserves, payroll, suppliers, and other committed future payments?

The app must show two parallel truths:

1. **Bank balance / saldo bancario**
   - What the bank account actually shows.
   - Example: an invoice payment arrives for 4,440 EUR, so the bank-like balance increases by 4,440 EUR.

2. **Spendable balance / disponibilita libera / budget spendibile**
   - What can actually be used without touching money already committed for VAT, F24, taxes, payroll, suppliers, subscriptions, etc.
   - Example: if the 4,440 EUR income includes 440 EUR of VAT, the bank-like balance shows +4,440 EUR, but the spendable balance reserves 440 EUR for VAT.

This feature should be added as a new module, not by rewriting all of Sure.

Suggested product name for user-facing UI:

> CavadaLabs Cashflow

Possible shorter internal namespace:

> Business Cashflow

---

## 2. Non-goals

Do not try to implement:

- Italian electronic invoicing / SDI
- Full accounting
- Double-entry bookkeeping
- VAT returns
- LIPE submission
- F24 generation
- Tax advice
- Payroll
- Bank PSD2 integration as a first step
- Replacing the commercialista

The app is a planning tool. It can estimate and reserve amounts, but final tax numbers must be confirmed by the commercialista or official fiscal software.

---

## 3. Branding and naming requirements

The fork is for CavadaLabs internal use.

User-facing naming should become:

- App/product name: **CavadaLabs Cashflow**
- Company/owner: **CavadaLabs**
- Main navigation item: **Business Cashflow** or **Cashflow Aziendale**
- Main metric: **Disponibilita libera**
- Secondary metric: **Saldo bancario**
- Tax reserve metric: **Accantonamenti IVA/F24**

Important license/trademark note:

- Keep upstream license files and attribution unless there is a clear legal reason not to.
- Do not falsely present upstream Sure/Maybe work as entirely original CavadaLabs code.
- Rebrand user-facing text/logo for internal usage, but preserve license notices.
- Do not remove AGPL/license attribution automatically.

Implementation preference:

- Add a config value or constant for app name, e.g. `CavadaLabs Cashflow`.
- Replace obvious user-facing occurrences of `Sure` only where appropriate.
- Do not blindly replace every occurrence in source code, tests, package names, or upstream documentation unless safe.
- If the app has a central branding helper/component, use it.

---

## 4. Core concepts

### 4.1 Bank balance

This is the actual account balance based on real transactions or manually entered current balance.

Example:

```
Starting bank balance: 10,000 EUR
Invoice paid by client: +4,440 EUR
Bank balance: 14,440 EUR
```

The bank balance should intentionally look similar to the real bank account.

### 4.2 Spendable balance / disponibilita libera

This is the amount that can be safely spent.

Formula v1:

```
Spendable balance =
  bank balance
  - active tax reserves
  - committed future outflows
  + confirmed future inflows included in planning
```

There should be a setting for whether confirmed future inflows are included in spendable balance. Default should probably be false for conservative planning.

Conservative formula v1 default:

```
Spendable balance today =
  bank balance
  - active VAT reserve
  - active tax/F24 reserves
  - committed future outflows within planning horizon
```

Planning horizon default: current quarter + next 30 days, or 90 days. Make this configurable.

### 4.3 Reserved money / accantonamenti

Reserved money is money present in the bank account but not really spendable.

Examples:

- IVA a debito
- F24 already expected
- INPS / INAIL
- IRES / IRAP estimate
- payroll
- supplier invoices already received
- rent
- recurring SaaS/software
- loan payments

Reserved money should be visible separately from normal expenses.

### 4.4 Committed vs planned

Every future event should have a status.

Suggested statuses:

- `draft`: entered but not used in calculations yet
- `planned`: expected but uncertain
- `committed`: should be treated as already reserved / not spendable
- `paid`: already happened
- `cancelled`: ignored

Default calculation:

- `committed` future outflows reduce spendable balance immediately.
- `planned` future outflows appear in forecasts but do not reduce conservative spendable balance unless the user enables it.
- `paid` affects bank balance through actual transactions.
- `cancelled` is ignored.

### 4.5 Expected vs confirmed income

Incoming money should also have a status.

Suggested statuses:

- `expected`: possible income, not guaranteed
- `confirmed`: invoice sent or payment reasonably expected
- `received`: already received in the bank
- `late`: overdue
- `cancelled`: ignored

Default calculation:

- `expected` income appears in optimistic scenario only.
- `confirmed` income appears in forecast.
- Conservative spendable balance should not include future income by default.
- `received` income becomes part of bank balance.

---

## 5. VAT logic for Italian business use

### 5.1 Income with VAT

When adding an income, the user must be able to enter:

- Gross amount / importo lordo
- VAT amount / IVA inclusa
- Net amount / imponibile
- VAT rate, optional
- Manual VAT override
- Expected payment date
- Client name
- Status
- Linked account
- Notes

Example:

```
Client invoice received: 4,440 EUR
VAT component: 440 EUR
Net revenue: 4,000 EUR
```

The app should show:

```
Bank-like income: +4,440 EUR
VAT reserve increase: +440 EUR
Spendable increase: +4,000 EUR
```

This is the key feature.

The user wants the bank balance to remain realistic, because the bank will show 4,440 EUR.
But the user also wants the budget/spendable balance to know that 440 EUR should not be touched.

### 5.2 Manual VAT amount is required

Do not assume all invoices use 22% VAT.

The UI should support:

- VAT rate 22%
- VAT rate 10%
- VAT rate 5%
- VAT rate 4%
- VAT rate 0%
- reverse charge / non-taxable / out of scope as future optional categories
- custom VAT amount

In MVP, always allow manual VAT amount because the user may want to enter real values from invoices.

### 5.3 Expenses with VAT credit

When entering an outgoing payment, the user should be able to enter:

- Gross amount paid
- VAT amount included in the expense
- Net cost
- Supplier
- Due date
- Payment date
- Status
- Category

Example:

```
Supplier bill paid: -1,220 EUR
VAT credit: 220 EUR
Net cost: 1,000 EUR
```

The bank balance decreases by 1,220 EUR because that is what leaves the bank.
But the VAT reserve should be reduced by 220 EUR because it may offset VAT payable.

Suggested calculation:

```
VAT payable reserve = VAT on sales - deductible VAT on purchases
```

Keep this simple in v1:

- Store VAT on income as `vat_debit_cents`.
- Store VAT on expenses as `vat_credit_cents`.
- For each VAT period, show:

```
IVA a debito: total VAT from incomes
IVA a credito: total deductible VAT from expenses
IVA stimata da versare: max(IVA a debito - IVA a credito, 0)
Credito IVA stimato: max(IVA a credito - IVA a debito, 0)
```

Do not generate official tax numbers. Label as estimate.

### 5.4 VAT period assignment

Each income/expense with VAT should belong to a VAT period.

For MVP:

- Assign by transaction/invoice date.
- Allow manual override of VAT period.
- Default regime: quarterly VAT.
- Allow switching to monthly in settings later.

Potential VAT period model:

```
TaxPeriod
- id
- organization/user id
- kind: vat
- period_type: monthly / quarterly
- year
- quarter or month
- start_date
- end_date
- due_date
- status: open / reviewed / closed / paid
- estimated_vat_debit_cents
- estimated_vat_credit_cents
- estimated_vat_due_cents
- manual_adjustment_cents
- notes
```

### 5.5 Default Italian quarterly VAT deadlines

Use configurable defaults, not hard-coded legal truth.

For ordinary quarterly VAT payments, default due dates:

- Q1 VAT: 16 May of the same year
- Q2 VAT: 20 August of the same year
- Q3 VAT: 16 November of the same year
- Q4 VAT: 16 March of the following year

If a date falls on a weekend or public holiday, the real deadline may shift. For MVP, support manual override and show a warning: "verify with commercialista".

Official reference to include in developer notes:

- Agenzia delle Entrate, F24 IVA periodica: quarterly taxpayers pay by the 16th day of the second month after each of the first three quarters: 16 May, 20 August, 16 November.
- Agenzia delle Entrate, LIPE: periodic VAT communications are submitted electronically by the last day of the second month after each quarter.

Store these as defaults in code, not as final fiscal advice.

---

## 6. Dashboard requirements

Add a new dashboard page:

Route suggestion:

```
/business-cashflow
```

Navigation label:

```
Business Cashflow
```

Italian UI label option:

```
Cashflow Aziendale
```

Main cards:

1. **Saldo bancario**
   - Current real balance from linked/manual accounts.

2. **Disponibilita libera**
   - Bank balance minus committed reserves/outflows.

3. **IVA accantonata**
   - Estimated VAT currently reserved.

4. **Uscite impegnate**
   - Committed future outflows inside planning horizon.

5. **Incassi confermati**
   - Confirmed future inflows.

6. **Punto minimo previsto**
   - Lowest projected balance in next 30/60/90 days.

7. **Prossima scadenza fiscale**
   - Next VAT/F24/tax due date.

### 6.1 Example card output

```
Saldo bancario: 14,440 EUR
IVA accantonata: -440 EUR
Uscite impegnate: -2,300 EUR
Disponibilita libera: 11,700 EUR
Saldo previsto a 30 giorni: 9,900 EUR
Punto minimo nei prossimi 90 giorni: 7,200 EUR
```

### 6.2 Timeline view

Add a timeline/table of future events.

Columns:

- Date
- Type
- Description
- Amount
- VAT component
- Status
- Effect on bank balance
- Effect on spendable balance
- Running projected bank balance
- Running projected spendable balance

Example:

```
2026-06-05  SaaS subscription      -120   committed   bank -120   spendable -120
2026-06-16  F24 VAT payment        -440   committed   bank -440   spendable 0 if already reserved
2026-06-20  Client invoice         +4440  confirmed   bank +4440  spendable +4000, reserve +440
```

Important: when paying VAT that was already reserved, the spendable balance should not drop again. It was already reduced when the VAT reserve was created.

---

## 7. Core calculation rules

### 7.1 Terminology

- `bank_balance`: real account balance
- `vat_reserve`: estimated VAT payable not yet paid
- `tax_reserve`: other taxes/F24/manual reserves
- `committed_outflows`: future payments marked committed
- `confirmed_inflows`: future income marked confirmed
- `free_cash`: spendable balance

### 7.2 Conservative free cash

Default:

```
free_cash = bank_balance - vat_reserve - tax_reserve - committed_outflows_within_horizon
```

Do not include future income unless the setting says so.

### 7.3 Forecasted bank balance

For a future date:

```
forecast_bank_balance(date) =
  current_bank_balance
  + received/confirmed inflows up to date
  - committed/planned outflows up to date
```

Scenario settings define which statuses are included.

### 7.4 Forecasted free cash

For a future date:

```
forecast_free_cash(date) =
  forecast_bank_balance(date)
  - VAT reserve remaining as of date
  - tax reserves remaining as of date
  - committed future outflows after date but inside horizon
```

Simpler MVP alternative:

```
forecast_free_cash(date) =
  forecast_bank_balance(date)
  - unpaid reserves still open on that date
```

### 7.5 Avoid double subtraction of VAT

Critical rule:

If VAT has already been reserved, paying the VAT later should reduce bank balance but should not reduce free cash again.

Example:

Initial:

```
Bank: 4,440
VAT reserve: 440
Free cash: 4,000
```

On VAT payment date:

```
Bank: 4,000
VAT reserve: 0
Free cash: 4,000
```

The VAT payment does not make the user poorer at payment time because the money was already marked as unavailable.

---

## 8. Data model proposal

This is a proposed Rails-ish model design. Codex should adapt to the actual Sure codebase conventions.

### 8.1 BusinessCashflow::Event

Represents any future or actual business cashflow event.

Fields:

```
id
user_id or family_id/account_owner_id, depending on Sure architecture
account_id nullable
kind enum: income, expense, tax_payment, reserve_adjustment, transfer
status enum: draft, planned, committed, confirmed, paid, cancelled, late
name string
counterparty string nullable
amount_cents integer, signed or positive plus direction
direction enum: inflow, outflow
currency string default EUR
event_date date
payment_date date nullable
vat_amount_cents integer default 0
vat_direction enum: debit, credit, none
net_amount_cents integer nullable
vat_rate decimal nullable
vat_manual boolean default false
category string
recurrence_rule string nullable
source enum: manual, imported, generated, linked_transaction
linked_transaction_id nullable
linked_tax_period_id nullable
notes text
created_at
updated_at
```

Notes:

- For income with VAT, use direction `inflow`, amount gross positive, VAT direction `debit`.
- For expense with deductible VAT, use direction `outflow`, amount gross positive, VAT direction `credit`.
- Tax payment events reduce bank balance and reduce the matching reserve.

### 8.2 BusinessCashflow::TaxPeriod

```
id
user_id or family_id
kind enum: vat
period_type enum: monthly, quarterly
period_key string e.g. 2026-Q2 or 2026-05
year integer
quarter integer nullable
month integer nullable
start_date date
end_date date
due_date date
status enum: open, reviewed, closed, paid
vat_debit_cents integer default 0
vat_credit_cents integer default 0
vat_due_cents integer default 0
manual_adjustment_cents integer default 0
notes text
created_at
updated_at
```

### 8.3 BusinessCashflow::Settings

```
id
user_id or family_id
vat_regime enum: quarterly, monthly
include_confirmed_income_in_free_cash boolean default false
include_planned_outflows_in_free_cash boolean default false
planning_horizon_days integer default 90
default_vat_rate decimal default 22.0
country string default IT
currency string default EUR
created_at
updated_at
```

### 8.4 BusinessCashflow::Reserve

Optional if not using TaxPeriod only.

```
id
user_id or family_id
kind enum: vat, f24, inps, inail, ires, irap, payroll, supplier, other
name string
amount_cents integer
due_date date nullable
status enum: active, paid, cancelled
source_event_id nullable
notes text
created_at
updated_at
```

---

## 9. UI requirements

### 9.1 New navigation section

Add main nav item:

```
Business Cashflow
```

or Italian:

```
Cashflow Aziendale
```

### 9.2 Dashboard page

Route:

```
/business-cashflow
```

Content:

- Summary cards
- Forecast chart
- Timeline of upcoming events
- VAT reserve card
- Upcoming fiscal deadlines
- Buttons:
  - Add income
  - Add expense
  - Add tax reserve
  - Add committed payment
  - Generate VAT periods

### 9.3 Add income form

Fields:

- Client / counterparty
- Description
- Gross amount
- VAT mode:
  - no VAT
  - VAT rate
  - manual VAT amount
- VAT amount
- Net amount auto-calculated but editable
- Invoice date
- Expected payment date
- Status: expected, confirmed, received
- Account
- Category
- Notes

Important UX:

Show a live preview:

```
Bank effect: +4,440 EUR
VAT reserve: +440 EUR
Spendable effect: +4,000 EUR
```

### 9.4 Add expense form

Fields:

- Supplier / counterparty
- Description
- Gross amount
- VAT deductible amount
- Net cost
- Due date
- Status: planned, committed, paid
- Category
- Account
- Notes

Live preview:

```
Bank effect: -1,220 EUR
VAT credit: +220 EUR
Spendable effect now: -1,220 EUR, but future VAT reserve reduced by 220 EUR
```

### 9.5 Tax settings page

Route:

```
/business-cashflow/settings
```

Fields:

- VAT regime: quarterly / monthly
- Default VAT rate
- Planning horizon days
- Include confirmed future income in free cash? yes/no
- Include planned expenses in free cash? yes/no
- Next VAT due dates editable
- Warning text: "Planning estimate only. Verify with your accountant."

---

## 10. Italian defaults

### 10.1 Categories

Seed or default categories:

Income:

- Client invoice
- Consulting
- Software/project income
- Other business income

Expenses:

- F24
- IVA
- INPS
- INAIL
- IRES
- IRAP
- Payroll / collaborators
- Supplier
- Accountant / commercialista
- SaaS / software
- Rent
- Hardware
- Bank fees
- Loan / financing
- Tax reserve
- Other

### 10.2 VAT deadlines

Default quarterly VAT calendar:

```
Q1: due 16 May
Q2: due 20 August
Q3: due 16 November
Q4: due 16 March of following year
```

Implementation:

- Generate periods for current year and next year.
- Allow manual editing of due dates.
- If due date falls on Saturday/Sunday, optionally shift to next Monday in UI but show editable warning.
- Do not claim official compliance.

---

## 11. Implementation phases

### Phase 0 - Repository inspection

Codex should inspect the Sure fork and produce a plan before editing.

Find:

- Rails version
- Routing conventions
- Auth/user/family/account ownership model
- Existing Account and Transaction models
- Existing UI components
- Test framework
- Styling system
- Locale/i18n system
- Existing branding constants

### Phase 1 - Branding minimal

- Add CavadaLabs Cashflow name to UI.
- Add CavadaLabs logo/name if there is a safe central place.
- Do not remove license files.
- Do not break upstream app startup.

### Phase 2 - Business Cashflow models

- Add migrations and models for events, settings, tax periods.
- Add enums and validations.
- Add tests.

### Phase 3 - Calculation service

Create service object:

```
BusinessCashflow::ProjectionService
```

Responsibilities:

- Calculate bank balance from existing accounts/transactions where possible.
- Calculate VAT debit/credit by tax period.
- Calculate reserves.
- Calculate free cash.
- Produce projected balances by date.
- Avoid double-subtracting VAT payments.

### Phase 4 - Basic CRUD

- Add income
- Add expense
- Add committed payment
- Add reserve/tax event
- Edit/delete events
- List events

### Phase 5 - Dashboard

- Summary cards
- Timeline
- Simple forecast chart
- VAT period summary
- Upcoming deadlines

### Phase 6 - Recurrences

- Add recurrence support for rent, SaaS, payroll, etc.
- Use existing recurrence library if present.
- Otherwise store RRULE string and expand in projection service.

### Phase 7 - Polishing

- Italian labels
- EUR formatting
- CSV import later
- Export later
- Better fiscal calendars later

---

## 12. Acceptance criteria

The MVP is successful when the user can do this:

1. Enter current bank balance or use existing Sure account balance.
2. Add a client income of 4,440 EUR with 440 EUR VAT.
3. See bank balance increase by 4,440 EUR.
4. See VAT reserve increase by 440 EUR.
5. See spendable/free cash increase only by 4,000 EUR.
6. Add a future F24/VAT payment for 440 EUR.
7. See that the payment reduces bank balance on payment date but does not reduce free cash twice.
8. Add future committed expenses like SaaS, commercialista, payroll.
9. See free cash today after subtracting committed future payments and reserves.
10. See projected balance at 7/30/60/90 days.
11. See upcoming VAT deadline based on quarterly defaults.
12. Manually override deadline/date/amount/status.

---

## 13. Edge cases

### 13.1 Income without VAT

Some income may have no VAT.

Effect:

```
Bank + amount
VAT reserve + 0
Spendable + amount
```

### 13.2 VAT credit exceeds VAT debit

If VAT credit > VAT debit:

```
VAT due = 0
VAT credit balance = VAT credit - VAT debit
```

Show separately as estimated credit. Do not add it automatically to spendable cash unless the user explicitly decides how to treat it.

### 13.3 VAT payment already manually entered

If user creates a tax payment linked to a tax period, mark reserve as paid or reduce reserve.

Avoid double count.

### 13.4 Future income uncertainty

Expected income should not make the user think money is spendable.

Use scenarios:

- Conservative: no future income included
- Base: confirmed income included
- Optimistic: expected income included with probability

### 13.5 Existing Sure transactions

Do not change existing transaction behavior in MVP.

Business Cashflow events can optionally link to existing transactions later.

---

## 14. Suggested Codex prompt

Use this prompt in Codex after adding this file to the repository.

```text
You are working inside a fork of the Sure finance application for CavadaLabs internal use.

Read the file `CAVADALABS_SURE_BUSINESS_CASHFLOW_SPEC.md` completely before making changes.

Goal:
Implement a CavadaLabs-branded Business Cashflow module for Italian small-business cash planning.

Core requirement:
The app must show both:
1. real bank balance / saldo bancario; and
2. spendable balance / disponibilita libera, which subtracts VAT reserves, tax/F24 reserves, and committed future outflows.

Important example:
If the user records an income of 4,440 EUR with 440 EUR VAT:
- bank-like balance should increase by 4,440 EUR;
- VAT reserve should increase by 440 EUR;
- spendable balance should increase only by 4,000 EUR.

If later the user records/pays the VAT/F24 for 440 EUR:
- bank balance decreases by 440 EUR;
- VAT reserve decreases by 440 EUR;
- spendable balance must not be reduced twice, because that VAT was already reserved.

Implementation instructions:
1. First inspect the codebase and identify Rails version, app structure, auth/ownership model, Account/Transaction models, routing conventions, test framework, UI styling/components, and branding constants/components.
2. Do not rewrite the existing Sure budgeting system.
3. Add a separate module/namespace called Business Cashflow or similar.
4. Use CavadaLabs Cashflow as the user-facing app/product name where appropriate.
5. Preserve upstream license files and attribution. Do not blindly remove Sure/Maybe references from license or legal files.
6. Add models/migrations/services/tests for business cashflow events, tax periods, and settings.
7. Implement a ProjectionService that calculates bank balance, VAT debit/credit/reserve, committed outflows, free cash, and projected balances.
8. Add basic CRUD UI for incomes, expenses, committed payments, and tax/VAT reserves.
9. Add dashboard route `/business-cashflow` with cards for saldo bancario, disponibilita libera, IVA accantonata, uscite impegnate, incassi confermati, projected balances, and upcoming fiscal deadlines.
10. Add quarterly Italian VAT defaults as editable planning defaults: Q1 due 16 May, Q2 due 20 August, Q3 due 16 November, Q4 due 16 March of following year. Do not present them as legal advice; add UI note to verify with commercialista.
11. Use EUR formatting by default.
12. Keep changes incremental and well-tested.

Deliverables:
- A short implementation plan before large edits.
- Database migrations.
- Models with validations/enums.
- Projection service with unit tests.
- Basic UI routes/pages/components.
- Navigation link.
- Minimal branding changes to CavadaLabs Cashflow.
- README or developer note explaining how to use the new module.

Acceptance test:
Create or describe a test scenario where:
- starting bank balance is 10,000 EUR;
- income is 4,440 EUR with 440 EUR VAT;
- committed future expense is 1,000 EUR;
- VAT reserve is 440 EUR;
- expected result is bank balance 14,440 EUR and spendable balance 13,000 EUR before paying VAT;
- after paying VAT, bank balance becomes 14,000 EUR and spendable balance remains 13,000 EUR, avoiding double subtraction.

Before coding, produce a concise plan listing files/modules you will touch. Then implement phase 1 through phase 3 first: branding minimal, data models, and ProjectionService tests. Do not attempt full UI until the calculation model is correct.
```

---

## 15. Suggested first issue list

Create GitHub issues or Codex tasks:

1. Inspect Sure architecture and produce implementation plan.
2. Add CavadaLabs Cashflow branding constant and user-facing name.
3. Add BusinessCashflow::Settings model.
4. Add BusinessCashflow::Event model.
5. Add BusinessCashflow::TaxPeriod model.
6. Add Italian quarterly VAT default generator.
7. Add ProjectionService with tests.
8. Add dashboard route and summary cards.
9. Add income form with VAT preview.
10. Add expense form with VAT credit preview.
11. Add timeline with running projected bank/free cash balances.
12. Add tax settings page.

---

## 16. Developer notes

Use integer cents for money. Avoid floats for stored money.

Allow manual overrides everywhere. Italian tax treatment has exceptions, and this is a planning tool.

The UI must make the distinction clear:

- Bank balance: what exists in the bank.
- Spendable balance: what can be used safely.
- Reserves: money that exists but should not be touched.

The most important product outcome is psychological clarity:

> The user should not have to remember in their head that part of the bank balance belongs to VAT/F24/taxes.

