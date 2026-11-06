# ADR-0024: Individual-only Android monetization

- Status: **Accepted** — user decision, November 1, 2026
- Product decision ID: `PD-M1-ANDROID-INDIVIDUAL-ONLY-001`
- Confirms: ADR-0008 Play Billing and network isolation

Android sells and restores the individual lifetime Unlimited product through Google
Play. The user explicitly chose “Keep Android individual-only and document the family
difference” instead of adding an account-and-invite entitlement service. Android
family access and discounted family upgrades are excluded from the Android parity
objective; they are intentional platform differences, not unfinished Android features.

Google Play Family Library does not share in-app purchases. The app therefore retains
its existing disclosure: Unlimited applies to the purchasing Google Play account,
in-app purchases are not shared through Family Library, and Apple purchases do not
transfer. No family SKU, discounted-family checkout, app account or family backend is
introduced. Lifetime purchase and restore still require real Play-account qualification.

The ledger preserves `cap.billing.family` and `cap.billing.family-upgrade` for iPhone
and iPad, removing Android from those two applicability lists. Their Apple status and
outcomes are retained; no Android family implementation or verification is claimed.
This is an explicit user-approved scope amendment, not an unavailable/deferred overlay
(which would intentionally leave the original objective blocked). All other scope,
including the separate grandfathering ledger row, is unchanged.

Source: [Google Play Family Library](https://support.google.com/googleplay/answer/7007852).
