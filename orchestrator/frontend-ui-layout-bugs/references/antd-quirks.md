# antd (v6) layout quirks

## InputNumber with addonBefore/addonAfter is not full width
- Mechanism: with a legacy addon, `InputNumber` returns `<Space.Compact>[addon]<InputNumber/>[addon]</Space.Compact>` (`input-number/index.js`, hasLegacyAddon branch). `style`/`className` go to the inner InputNumber; `rootClassName` goes to the Compact. Compact is `display:inline-flex` with no width (`space/style/compact.js`), so the group shrinks to content even with `width:100%`.
- Global fix (verified in harness, 566px field: 132-278px -> 566px):
  ```css
  .ant-space-compact:has(> .ant-input-number-addon) { display:flex; width:100%; }
  .ant-space-compact:has(> .ant-input-number-addon) > .ant-input-number { flex:1 1 auto; width:auto; min-width:0; }
  ```
  The rule also stretches inline uses (e.g. a "Tampilkan [n] produk" limit input in a filter bar then fills the whole row). Whether those get an opt-out class is the user's look decision: ask, don't assume an opt-out. Verified again from the production-built CSS: all addon variants fill their container, a `md=12` column fills its half, a no-addon InputNumber is unchanged. Per-site alternative: `rootClassName` with `width:100%` + flex on the inner.
- `addonBefore`/`addonAfter` are deprecated in favour of `Space.Compact` (`block` prop gives width 100%).

## Plain InputNumber has a fixed default width (~90px)
- `.ant-input-number` is `inline-flex` with `width: controlWidth`, so without a width it does not fill a form column. Global default `.ant-input-number { width:100% }` in the app stylesheet fills every container; deliberate `style={{ width: 84 }}` cells keep their size (inline style wins), verified in harness. The addon `:has()` rule above has higher specificity, so its inner `width:auto` still applies.
- Addon InputNumbers inside `<Space wrap>` fill only their Space item (content-sized), so toolbars keep their look under both rules.

## Other
- `Col md={x}` without `xs` shrinks to content below md.
- `Segmented` always highlights an option; give the field an initial value.
