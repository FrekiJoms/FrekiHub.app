# Wallet cards

Finance separates recorded money by payment method using card-shaped wallets. Each saved method shows its own balance, the summary card at the top shows the combined total, and the same wallets can be read as rows, a multi-column grid or a swipeable stack. The wallet scope also drives the month summary, safe-to-spend, category chart, planner and timeline rather than sitting beside them as a separate block.

## Reference analysis: Agila

The wallet treatment was modelled on **Agila: Finance Coach**, a Philippine personal-finance app. Public App Store/Google Play screenshots, release notes and the developers' wallet tutorial show the following behavior:

- A dark summary card sits above the wallet list. It carries the combined balance with a hide/reveal control and secondary metrics such as assets and liabilities.
- Wallets are drawn as full-bleed payment cards rather than list rows: chip or contactless mark, network mark, card name and the wallet's own balance.
- The wallet screen supports a two-column card grid; a home carousel shows the same full card art.
- Holding a wallet enters rearrangement, so card order is a user choice rather than a fixed alphabetical list.
- Later releases added custom wallet designs: upload a logo or a full card image and reposition it inside the card frame.

FrekiHub keeps those interaction ideas but not Agila's proprietary artwork. Built-in cards are original painted gradients/patterns with text wordmarks. No bank logo, account number or card number is bundled, fetched or inferred.

## What Finance shows

`WalletSection` is the first block on Finance and now carries the month navigation too.

1. **Total card** — combined all-time balance of wallets included in the total, a hide/reveal toggle, assets (positive wallets), owed (negative wallets) and the included wallet count. It always covers all wallets, so it is labelled separately from the month figures.
2. **Month card** — the month pager, month net for the current scope, elapsed-period ring, safe-to-spend, and income/spent/saved metrics. A scope chip in the card opens the wallet picker. There is no second "net position" card.
3. **Toolbar** — one-line guidance, the rows/multi/stack switch and an add-wallet action.
4. **Wallet views**
   - **Rows**: compact list with balance, inclusion state, planned amount and drag handle.
   - **Multi**: two columns on phones, three on wide layouts, full card art per wallet.
   - **Stack**: up to four layered cards. The front card accepts a swipe in any direction; it flies out along the gesture and moves to the back of the stack. Previous/next buttons perform the same reorder without a gesture.
5. **Card menu** (ellipsis or long press): scope Finance to the wallet, edit design, move to front, include/exclude from the top total, add another wallet.
6. **Wallet detail**: large card, balance, lifetime saved, planned outflows, design shortcut, scope shortcut and the eight most recent movements.

The selected wallet also outlines its card in grid, rows and stack views, so the active scope is visible without opening the picker.

Opening Finance does not enable location, notifications or purchase scanning.

## Finance integration

Finance uses one wallet scope across its sections:

- **All wallets** (default) keeps the whole-ledger view. Selecting a wallet narrows the month net, safe-to-spend, income/spent/saved metrics, category chart, planner rules and expected/actual timeline to that method.
- The scope is session state. It is not stored, so a fresh launch returns to **All wallets** rather than hiding records unexpectedly.
- Planned expenses and savings already carry a payment method through the planner rule. Card artwork shows the formatted amount followed by `planned` under the balance for the selected month whenever a future planned occurrence targets that wallet. Planned money is a commitment only: it reduces scoped safe-to-spend but does not change the wallet balance until the occurrence is recorded.
- The savings goal remains one shared goal per currency. With a wallet scoped, the goal card shows that wallet's lifetime savings and its share of the shared goal. With all wallets, it lists each wallet's contribution; tapping a contribution scopes Finance to it.
- Planner reordering while a wallet is scoped rewrites positions across the full rule list, so hidden rules do not collide with visible ones.
- New rules added while a wallet is scoped default to that wallet's payment method. The planner row shows the method, and planned rows in the timeline show the method they will use.

## Money rules

Wallets are derived from the existing ledger; there is no wallet table or balance column to keep in sync.

- A wallet's balance is the current display currency's recorded `income` minus `expense` minus `savings` for that payment method. This matches the all-time `budget.balance` semantics, not the selected month.
- The month card and lower Finance sections use recorded entries for the selected month and wallet scope. Safe-to-spend is scoped month net minus remaining planned outflows for that scope.
- Wallets are the saved payment methods plus any method still referenced by a transaction in the display currency, so separated balances add up to the ledger balance.
- Blank legacy payment methods belong to **Cash**.
- Other currencies stay isolated; switching currency changes the displayed wallets and balances without converting values.
- Excluding a wallet removes it from the summary total only. It stays visible with an `EXCLUDED` label and remains available to transactions.
- There is no bank connection. A balance reflects records the user saved; it is not a statement balance.

## Order and persistence

One wallet order is shared by rows, multi and stack views.

- Dragging a row, swiping a stack card or choosing **Move card to front** saves the new order through the `walletOrder` preference.
- New methods that are not in the saved order are appended, ordered by absolute balance and then name.
- The order is restored on the next launch; unknown or removed method names are ignored.
- A failed order write shows the error pill and restores the previous visible order instead of pretending the change was saved.
- The swipe animation follows the drag/fling direction. With reduced motion enabled, the same reorder completes without the flight animation.
- Card view (`rows`, `grid`, `stack`), the amount-mask toggle and the card order are remembered. The Finance wallet scope is intentionally not persisted and resets to **All wallets** on launch.

## Card artwork

`WalletSkin` provides original presets for common Philippine wallets and generic accounts: GCash, Maya, BPI, Metrobank, RCBC, BDO, ShopeePay, PayPal, Wise, Atome, UnionBank, Cash, Bank, Card and Ink. A method name selects a matching preset; an unknown name uses the neutral Ink card.

Per-wallet design preferences:

- `wallet:<name>:style` — preset id or `custom`.
- `wallet:<name>:image` — absolute path to a copied image in the app-support `wallet-cards/` folder.
- `wallet:<name>:scale`, `wallet:<name>:dx`, `wallet:<name>:dy` — normalized zoom and pan stored when the user repositions uploaded art.
- `wallet:<name>:include` — `false` for a wallet excluded from the top total.

Custom artwork uses the existing image picker. Images are copied into app support storage, limited to 12 MB, replaced atomically with the preference update, and deleted when no longer referenced. The balance, wallet name, mask state and menu stay above the artwork, so a full-card design cannot hide the amount. Uploaded artwork is device-local: JSON backups retain the design style but omit the absolute image path, and restoring on another device falls back to the matching preset.

## Rule and data exposure

`budget.wallet_count` reports the number of wallets in the display currency, including saved methods and methods referenced by current-currency transactions. Planner rules already expose their `method`; Finance now uses that method for scoping, commitments and new-rule defaults. Per-wallet design keys remain readable through the generic `data.get("settings.wallet…")` preference path; balances are not duplicated into rule snapshots beyond the existing budget fields. No wallet or allocation table was added.

## Code map

- `lib/data.dart` — `walletMethods`, `walletBalances`, `walletBalance`, `walletEntries`, `scopedEntries`, `savingsByWallet`, `orderedWalletNames`, backup image filtering.
- `lib/wallets.dart` — view enum, skins, card renderer, artwork picker, account/commitment helpers, `FinanceMonth` month math.
- `lib/wallet_views.dart` — Finance total/month cards, scope picker, toolbar, rows/grid/stack, detail/menu/design/add sheets.
- `lib/budget.dart` — composes the wallet section with the savings goal, scoped chart, planner and timeline.
- `lib/forms.dart` — planner form's wallet default when Finance is scoped.
- `lib/rule_language.dart` — `budget.wallet_count` catalog field and snapshot value.
- `test/wallet_test.dart` — balance, currency, scope, commitment, goal-contribution, order, skin, backup and stack-swipe persistence checks.

## Verification boundaries

Automated checks cover wallet arithmetic, currency isolation, blank-method normalization, month/scope totals, safe-to-spend commitments, per-wallet savings, order parsing, skin selection, include/custom preferences, backup filtering, and a widget test that swipes the stack and asserts the saved `walletOrder`. `flutter analyze` is clean. Device checks still needed: the actual drag feel on the phone, custom-art pan/zoom framing across cards, and restart restoration after a real process death.
