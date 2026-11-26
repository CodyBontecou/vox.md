# Retired custom analytics service

Custom app analytics, installation identifiers, advertising joins and event ingestion have been removed from the candidate app. The replacement Worker acknowledges legacy POST /v1/events with 204 without reading its body or using storage. This prevents older clients from repeatedly retrying a retired upload. GET /health reports retirement. Other endpoints return 410. The candidate configuration has no storage bindings, logging or cron triggers.

Deployed 2026-11-26 (version 4187186c-84cc-444d-b925-348b47b03274) after owner approval. Older released clients still upload, but the Worker discards their events; the D1 and cron bindings were dropped from the Worker. The existing D1 database `voxboard-onboarding-analytics` (1,042 rows, newest 2026-07-27) is kept by owner decision and is not deleted. Historical SQL migrations are retained as deployment provenance; do not apply the abandoned shared-privacy migration. Essential receipt verification, scheduling, OAuth and user-requested destinations are separate services and remain intact.

## Existing data and retirement review

After owner approval, replace ingestion first, verify no further writes, then erase the dedicated analytics database (`onboarding_events` and any analytics-only indexes/tables), exports and query artifacts. Inventory provider logs, local operator exports, and recovery copies; record actual expiry/deletion dates. Do not promise that uninstalling an app erases server data or that backups have already expired. Do not reuse old install IDs to join records to essential services. Schedule a separate approved cleanup of abandoned resources/secrets. Keep this responder for old clients until a later retirement decision.

Review existing deployment identity and database ownership before destructive operations. No remote cleanup, migration, resource deletion, submission or release is authorized by this local change.

Run `npm test` and `npm run typecheck` for the local retirement responder.
