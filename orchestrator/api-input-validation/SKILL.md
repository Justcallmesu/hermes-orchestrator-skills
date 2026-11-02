---
name: api-input-validation
description: "Use when validating or renaming API request fields."
---

# API input validation for numeric and money fields

For DTO / request-schema validation where a wrong value silently becomes data (a cost of 0, an
amount, a quantity). Project decorators and pipe settings come from the repo; read them first.

## Procedure
1. **Find how the field is converted before it is validated.** Open the decorator the DTO uses
   (e.g. a project `RequiredNumber` / `OptionalNumber`) and the global pipe setup (`main.ts`:
   `transform`, `enableImplicitConversion`, `transformOptions`, any `APP_PIPE`). A transformer that runs
   `Number(value)` first turns `""`, `" "`, `false` and `[]` into 0.
2. **Decide what 0 means for this field.** If 0 is a meaningful stored value (clears a flag, a free
   item, a zero payment), coercion lets an unset value become real data. Use a non-coercing
   validator chain (class-validator: `@IsNotEmpty() @IsNumber() @Min(0)`, no `@Type`/`ToNumber`) so the
   raw JSON type must already be a number. Decide explicitly whether numeric strings (`"0"`) are
   accepted; refuse them unless the project accepts them elsewhere and clients need it.
3. **Watch bound changes.** Relaxing a lower bound from `> 0` to `>= 0` (or `min: 0.0001` to `min: 0`)
   removes the accidental protection that refused the coerced 0. Every such change re-runs step 1.
4. **Test raw bodies over real HTTP**, not DTO objects: send the exact bytes
   (`.set('Content-Type','application/json').send('{"unitCost":""}')`) through the real pipe. Table-test:
   `""`, `" "`, `"\t"`, `false`, `true`, `[]`, `[0]`, `{}`, missing field, `null` (field and whole body),
   `"0"`, `"abc"`, `"NaN"`, `"Infinity"`, `1e400`, a negative, a sub-scale negative (`-0.00004`), then the
   valid ones (`0`, `-0`, `0.0`, a sub-scale positive, a normal value). For each refused body assert the
   400 AND that the stored row and audit rows are untouched.
5. **RED first, then mutate.** Run the new cases against the old DTO (they must fail as 200), then put
   the coercion back after the fix and watch exactly those cases fail.
6. **Scan siblings, report, don't widen scope.** Grep every coercing decorator with a 0 lower bound on
   money fields; list file:line and whether a service-level guard exists. Fixing them is its own ticket
   (it changes other modules' behaviour); log it as a backlog row.

## Pitfalls
- class-validator `@IsOptional()` lets `null` through as well as a missing field. A service that only
  checks `!== undefined` then crashes on `null.trim()` (500) or writes NULL into a NOT NULL column. Treat
  null as absent in ONE "is present" helper (`value != null`), or reject it with `@ValidateIf`/`IsDefined`,
  and test `null` per optional field on every endpoint that takes the DTO. Have the webapp omit empty
  optional fields instead of sending `null`.
- A check and the write must resolve an OMITTED field to the same value. When a policy/validator
  defaults a missing enum one way (discount type -> AMOUNT) and the service stores it another way
  (-> PERCENT), `discountValue: 90` with no type passes the floor check as Rp 90 and is charged as
  90 %. Resolve the default ONCE per line/header with one shared helper, pass that resolved value
  to both the check and storage, and make the policy's own fallback match the stored default.
  Grep every `?? <Enum>.` fallback of the field across services and the policy util; test each
  document type with the field omitted and assert both the 400 and the stored type.
- An edit endpoint that decides "did this field change?" (to refuse or to rewrite a derived stored
  value, e.g. a lot cost per base unit behind a Harga Pokok per PO unit) must compare the submitted
  value with exactly what the edit form SHOWS for that line: the stored value converted with the
  factor the line was POSTED with (not today's product factor), rounded the way the form rounds, with
  the same fallback the form uses when the stored value is null. An omitted field means unchanged.
  Re-deriving `submitted / factor` and comparing with the stored value misfires whenever the stored
  value is not exactly "default / factor" (null opening-stock rows, >2-decimal verified prices,
  API calls without the field): a no-op save gets refused or silently rewrites data. Test a no-op
  save for each of those three shapes, plus a real change on a used and an unused row.
- Max-decimals rule (qty/money stored as `decimal(n,2)`): add one opt-in decorator option
  (`maxDecimalPlaces`) with its own check `Number(value.toFixed(places)) === value`, not
  class-validator's `IsNumber({ maxDecimalPlaces })`, which splits `value.toString()` and throws on
  exponent forms like `1e-7` (a 500, not a 400). Float dust (`0.1+0.2`) is refused too, so the
  matching FORM inputs need `precision={2}` in the same wave: a form that used to round silently
  now meets a 400 the user cannot explain. List every form that posts the field in the brief.
- Renaming or removing a request field: first read the global pipe (`whitelist`,
  `forbidNonWhitelisted`). With `whitelist: true, forbidNonWhitelisted: false` an old cached client
  that still sends the old field gets a 201 and its intent is silently dropped (e.g. a money option
  not applied). Keep the old field on the DTO only to REFUSE its meaningful value with a 400 that
  tells the user to reload, test that case over HTTP, and ship server + client together.
- When a read-only preview endpoint feeds a client choice (which rows may be ticked), pin down how
  "not eligible" is expressed: a row with 0 vs no row at all. The client must treat a missing row as
  not eligible, and the create endpoint must apply the same shared rule as the preview, so preview
  and save never disagree.
- A frontend that never sends a blank does not protect the API; the HTTP probe is the evidence.
- `-0` arrives as a number and passes `Min(0)`; normalise it (`x + 0`) before storing or comparing.
- A UI confirm for a meaningful 0 ("cost 0 = free/bonus, continue?") needs a guard against opening
  twice (a ref flag reset in the dialog's after-close hook) and must send nothing on cancel.
- Tests comparing stored audit/child rows against an expected list must sort both sides by the same
  key; rows read without ORDER BY (or ordered by uuid) make the new test intermittent.
