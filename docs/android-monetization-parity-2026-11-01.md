# Android monetization parity — November 1, 2026

## Lifetime purchase and restore

The native individual lifetime product remains `vox_unlimited_lifetime`, a Google Play
non-consumable. This update hardens its existing purchase/restore path:

- Checkout uses the exact eligible Play offer token paired with the displayed price.
  Rental and preorder options are excluded from the lifetime product presentation.
- Already-owned, pending, restoring and in-flight states cannot launch another checkout.
  Busy states are visible and disable conflicting purchase/restore actions.
- Query generations reject late ownership/product callbacks. Explicit restore intent
  survives overlapping foreground refresh and purchase callbacks; a response applies once.
- Immediate cancellation preserves access; `ITEM_ALREADY_OWNED` performs ownership
  reconciliation instead of reporting a failed purchase or opening another checkout.
- Acknowledgement requests are coalesced in memory. Failures retain verified access,
  expose a restore/retry message, and can be retried on the next ownership query.
- Existing installation/product-bound HMAC cache, pending/refund rules, privacy-safe
  diagnostics and separation from capture content remain in force.

## Family access and discounted family upgrade

These remain unresolved implementation scope, not enabled purchase products. Google
Play Family Library does not share in-app purchases. The repository currently has no
app-account entitlement service, and ADR-0008 explicitly records individual-only
Android access until a separate account/backend design exists.

A direction question is pending: build an account-and-invite family service, integrate
an existing service, or retain the disclosed Android platform difference. An actual
family implementation needs identity, server-side Play purchase verification, ownership
binding, family invitations/membership, revocation and restore. Discounted upgrade
eligibility must be verified against an existing individual entitlement; creating a
second cheap Play product and gating it only in client UI would not enforce eligibility.

No family or discounted-family purchase is advertised as shareable without that service.
Apple purchases and grandfathering remain Apple-only under the current policy.

Sources: [Play Family Library](https://support.google.com/googleplay/answer/7007852),
[one-time product offers](https://developer.android.com/google/play/billing/one-time-product-multi-purchase-options-offers),
[Play purchase lifecycle](https://developer.android.com/google/play/billing/lifecycle/one-time),
and `docs/architecture/adr-0008-play-billing-network-isolation.md`.

## Validation

Full checks and clean-commit oracle provenance will be recorded after completion.
Actual Play license-account purchase, pending payment, acknowledgement, refund and
reinstall/restore campaigns remain account qualification; fixture/UI checks do not
claim real store transactions.
