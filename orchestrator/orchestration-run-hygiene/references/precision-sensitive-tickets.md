# Tickets that change stored money or other precise values

Applies to any ticket whose change can alter an amount, quantity or total that is stored, posted or
shown to an external party (invoices, ledgers, stock valuation, tax).

- Red-team the design with a fresh reviewer before cutting tickets.
- Brief STOP conditions: a stored/posted value would change, a non-target line moves by even the
  smallest unit, an assumption about how a header total is composed fails.
- Reviewer sweeps the new formula against the database's own rounding function and the frozen HEAD
  formula (non-target lines byte-identical), and checks that partial operations (receipts, returns,
  split payments) sum exactly to the whole.
- Pieces of one fix that are consistent only together are one release unit; record that as a decision
  so nothing is cherry-picked.
