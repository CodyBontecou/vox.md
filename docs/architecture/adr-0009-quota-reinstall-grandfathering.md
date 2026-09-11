# ADR-0009: Quota reinstall and grandfathering

- Status: **Accepted**
- Product decision IDs: `PD-M1-QUOTA-REINSTALL-001`, `PD-M1-GRANDFATHERING-001`
- Required by: M1, M3, and M8

## Context

Apple can retain usage/access evidence through Keychain and signed AppTransaction,
but quota records in the legacy macOS login Keychain can request the user's credentials
when a new build has a different code signature. Android has no approved Vox.md
account/backend or equivalent uninstall-resistant free-usage authority.

## Decision

Free transcription and Capture usage is installation-local on every platform. Vox.md
does not read or write free-usage quota state in Keychain. Removing the app's local data
creates fresh free counters; platform backups must not transfer quota state. A future
account/backend may change the policy only through a separately approved ADR covering
privacy, migration, abuse, and cross-device identity.

Within an installation, usage is metered only at the existing semantic success boundary
and is idempotent by stable request/delivery ID. Failed, cancelled, discarded, or
unverified destination work does not consume successful-delivery quota; committed
retries cannot double-charge while the local ledger remains.

Grandfathering is store/platform-specific:

- Apple preserves its shipped classification: only an Apple-signed AppTransaction whose
  original app build qualifies under the native Apple rule receives permanent original
  paid-app access; current StoreKit purchases follow current verified entitlement.
- Android grants no Apple paid-app grandfathering and has no historical Android paid
  cohort at M1. Play access comes only from a verified recognized Play purchase. There
  is no device-date, preference, restored file, or self-asserted legacy-owner shortcut.

Existing-user messaging must distinguish free reset, verified Play restore, and
Apple-only grandfathered access without implying a cross-store account.

## Compatibility and consequences

The policy changes Apple's free-Capture reinstall behavior while preserving signed
AppTransaction grandfathering and current StoreKit entitlements. Legacy quota Keychain
items are ignored rather than queried or deleted, avoiding credential prompts from old
access-control lists. It accepts potential free-tier reset abuse rather than introducing
a content/account backend. Quota state remains separate from immutable pending content
and cannot cause content loss.

## Rejected alternatives

- **Persist quota in Keychain or fingerprint an uninstall-resistant ID:** rejected to
  avoid credential prompts, hidden persistence after uninstall, and cross-install identity.
- **Back up quota state:** rejected because backup is excluded by ADR-0006.
- **Import Apple entitlement to Android without an account/backend:** rejected as
  unverifiable cross-store authority.
- **Grandfather based on install date or a Boolean:** rejected because it is forgeable
  and conflicts with the shipped signed Apple classification.
- **Charge at attempt/enqueue:** rejected because failed work is not successful usage.

## Executable gates

- Metering tests prove reserve/commit/release and retry idempotency at successful
  transcription/delivery boundaries.
- Local-data-removal tests prove a missing Capture ledger starts with a fresh allowance;
  backup tests prove usage is not transferred.
- Entitlement tests cover verified Play restore and reject unknown/unverified products,
  Apple claims, dates, and legacy flags.
- Existing Apple tests continue covering signed original-paid-owner classification and
  current StoreKit reconciliation.

No uninstall or account evidence is fabricated here.
