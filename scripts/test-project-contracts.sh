#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Voxboard.xcodeproj/project.pbxproj"

# The physical-device launch gate must fail on late crashes, stale PIDs, and
# missing/failed JSON, even on runners without an attached Apple device.
python3 -m unittest discover -s "$ROOT/scripts/tests"

"$ROOT/scripts/validate-android-wear-m0.py"
python3 "$ROOT/Packages/contracts/scripts/convert_capabilities.py" --check
python3 "$ROOT/Packages/contracts/scripts/validate.py"
python3 "$ROOT/Packages/contracts/scripts/validate_toolchain.py"
python3 "$ROOT/Packages/contracts/scripts/validate_validation_definitions.py"
python3 -m unittest discover -s "$ROOT/Packages/contracts/tests"

python3 - "$ROOT" "$PROJECT" <<'PY'
from __future__ import annotations

from html.parser import HTMLParser
import ast
from pathlib import Path
import json
import os
import struct
from urllib.parse import urlsplit
import json
import re
import sys

root = Path(sys.argv[1])
project_path = Path(sys.argv[2])
project = project_path.read_text()
# OpenStep allows quoted keys and either dictionary key order.
project = re.sub(r'"([A-Z][A-Z0-9_]*)"\s*=', r'\1 =', project)
project = re.sub(r'= "([A-Za-z0-9_.]+)";', r'= \1;', project)
errors: list[str] = []

# Parse the project as an OpenStep property list rather than matching Xcode's
# serialization: Xcode (and other tools) may quote keys and values or reorder
# fields such as `isa`, and the contracts below must hold either way.
_PBX_TOKEN = re.compile(r'''\s+|/\*.*?\*/|//[^\n]*|"((?:[^"\\]|\\.)*)"|([A-Za-z0-9_$/:.\-+]+)|([{}()=;,])''', re.S)
def parse_pbxproj(text):
    tokens = []
    for match in _PBX_TOKEN.finditer(text):
        if match.group(1) is not None:
            tokens.append(('s', re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), match.group(1))))
        elif match.group(2) is not None:
            tokens.append(('s', match.group(2)))
        elif match.group(3) is not None:
            tokens.append(('p', match.group(3)))
    consumed = sum(len(m.group(0)) for m in _PBX_TOKEN.finditer(text))
    if consumed != len(text):
        raise ValueError('pbxproj contains unrecognized characters')
    position = 0
    def value():
        nonlocal position
        kind, token = tokens[position]; position += 1
        if kind == 's':
            return token
        if token == '{':
            result = {}
            while tokens[position] != ('p', '}'):
                key = value()
                if not isinstance(key, str) or tokens[position] != ('p', '='):
                    raise ValueError(f'pbxproj dictionary key expected near token {position}')
                position += 1
                result[key] = value()
                if tokens[position] != ('p', ';'):
                    raise ValueError(f'pbxproj ";" expected near token {position}')
                position += 1
            position += 1
            return result
        if token == '(':
            result = []
            while tokens[position] != ('p', ')'):
                result.append(value())
                if tokens[position] == ('p', ','):
                    position += 1
            position += 1
            return result
        raise ValueError(f'unexpected pbxproj token {token!r}')
    parsed = value()
    if position != len(tokens):
        raise ValueError('trailing pbxproj tokens')
    return parsed


def pbx_render(value) -> str:
    if isinstance(value, list):
        return '(\n' + ''.join(f'{pbx_render(item)},\n' for item in value) + ')'
    if isinstance(value, dict):
        return '{' + ''.join(f'{pbx_render(k)} = {pbx_render(v)}; ' for k, v in value.items()) + '}'
    if re.fullmatch(r'[A-Za-z0-9_$/.]+', value):
        return value
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def pbx_settings_text(settings: dict) -> str:
    """Canonical one-setting-per-line text, e.g. `IPHONEOS_DEPLOYMENT_TARGET = 17.6;`."""
    return '\n' + '\n'.join(f'{key} = {pbx_render(value)};' for key, value in settings.items()) + '\n'


try:
    project_objects = parse_pbxproj(project)['objects']
except (ValueError, IndexError, KeyError, TypeError) as error:
    errors.append(f'Xcode project cannot be parsed: {error}')
    project_objects = {}
build_configurations = [
    (item.get('name'), item.get('buildSettings', {}))
    for item in project_objects.values()
    if isinstance(item, dict) and item.get('isa') == 'XCBuildConfiguration'
]

purchase_source = (
    root / 'Packages/VoxboardShared/Sources/VoxboardShared/PurchaseAccess.swift'
).read_text()
storekit_config = json.loads((root / 'Voxboard/Voxboard.storekit').read_text())
# Hard paywall: lifetime non-consumables stay valid beside one Apple subscription
# group of weekly/yearly Individual and Family plans with an eligible 7-day trial.
if storekit_config.get('version') != {'major': 3, 'minor': 0} or 'nonConsumableProducts' in storekit_config:
    errors.append('Voxboard.storekit must use the StoreKit configuration v3 product layout')
storekit_products = {
    product['productID']: product
    for product in storekit_config.get('products', [])
}
expected_purchase_products = {
    'bontecou.Voxboard.unlock': False,
    'bontecou.Voxboard.family': True,
    'bontecou.Voxboard.familyUpgrade': True,
}
if set(storekit_products) != set(expected_purchase_products):
    errors.append(
        f'StoreKit lifetime product IDs are {sorted(storekit_products)}, '
        f'expected {sorted(expected_purchase_products)}'
    )
for product_id, family_shareable in expected_purchase_products.items():
    if product_id not in purchase_source:
        errors.append(f'PurchaseAccess does not recognize {product_id}')
    product = storekit_products.get(product_id)
    if product is None:
        continue
    if product.get('type') != 'NonConsumable':
        errors.append(f'{product_id} must remain a one-time NonConsumable purchase')
    if product.get('familyShareable') is not family_shareable:
        errors.append(
            f'{product_id} familyShareable={product.get("familyShareable")}, '
            f'expected {family_shareable}'
        )
if storekit_config.get('nonRenewingSubscriptions'):
    errors.append('StoreKit must not configure non-renewing subscriptions')
# The App Store Connect staging script is the source of truth for plan prices.
staged_subscription_products = {}
staged_source = (root / 'scripts/prepare-vox-subscriptions.py').read_text()
staged_match = re.search(r'^PRODUCTS = (\{.*?^\})', staged_source, flags=re.M | re.S)
if staged_match is None:
    errors.append('staged subscription policy PRODUCTS table is missing')
else:
    staged_subscription_products = {
        product_id: (price, name)
        for _, product_id, price, name in ast.literal_eval(staged_match.group(1)).values()
    }
subscription_groups = storekit_config.get('subscriptionGroups', [])
if len(subscription_groups) != 1:
    errors.append(f'StoreKit must configure exactly one subscription group, found {len(subscription_groups)}')
storekit_subscriptions = {
    subscription['productID']: (group, subscription)
    for group in subscription_groups
    for subscription in group.get('subscriptions', [])
}
expected_subscriptions = {
    'bontecou.Voxboard.individual.weekly': ('P1W', False),
    'bontecou.Voxboard.individual.yearly': ('P1Y', False),
    'bontecou.Voxboard.family.weekly': ('P1W', True),
    'bontecou.Voxboard.family.yearly': ('P1Y', True),
}
if set(storekit_subscriptions) != set(expected_subscriptions) or set(staged_subscription_products) != set(expected_subscriptions):
    errors.append(
        f'StoreKit subscriptions {sorted(storekit_subscriptions)} and staged products '
        f'{sorted(staged_subscription_products)} must both equal {sorted(expected_subscriptions)}'
    )
for product_id, (period, family_shareable) in expected_subscriptions.items():
    if product_id not in purchase_source:
        errors.append(f'PurchaseAccess does not recognize {product_id}')
    group, subscription = storekit_subscriptions.get(product_id, (None, None))
    if subscription is None:
        continue
    staged_price, staged_name = staged_subscription_products.get(product_id, (None, None))
    if subscription.get('type') != 'RecurringSubscription' or subscription.get('recurringSubscriptionPeriod') != period:
        errors.append(f'{product_id} must auto-renew every {period}')
    if subscription.get('familyShareable') is not family_shareable:
        errors.append(f'{product_id} familyShareable must be {family_shareable}')
    if subscription.get('subscriptionGroupID') != group.get('id'):
        errors.append(f'{product_id} must belong to its single shared subscription group')
    if subscription.get('displayPrice') != staged_price or subscription.get('referenceName') != staged_name:
        errors.append(f'{product_id} local StoreKit price/name differs from the staged subscription policy')
    if subscription.get('introductoryOffer') != {
        'internalID': subscription.get('internalID', '') + '-trial',
        'numberOfPeriods': 1,
        'paymentMode': 'free',
        'subscriptionPeriod': 'P1W',
    }:
        errors.append(f'{product_id} must offer exactly one free 7-day introductory trial')
    if subscription.get('groupNumber') != (1 if family_shareable else 2):
        errors.append(f'{product_id} must rank Family above Individual within the subscription group')

usage_tracker_source = (
    root / 'Packages/VoxboardShared/Sources/VoxboardShared/UsageTracker.swift'
).read_text()
for required in [
    'public static let freeMinutesLimit: Double = 0',
    'public static let freeCaptureLimit: Int = 0',
    'guard !product.isSubscription else { return }',
]:
    if required not in usage_tracker_source:
        errors.append(f'hard paywall access policy is missing {required}')
for pattern, label in [
    (r'public var isAtLimit: Bool \{\s*!hasUnlocked\s*\}', 'transcription'),
    (r'public var isCaptureAtLimit: Bool \{\s*!hasUnlocked\s*\}', 'Capture'),
]:
    if not re.search(pattern, usage_tracker_source):
        errors.append(f'{label} must require paid access with no free allowance')
readme_source = (root / 'README.md').read_text()
for required in [
    'requires paid access for new Capture deliveries and transcription',
    'Eligible subscriptions include a 7-day free trial',
    'Lifetime is a one-time purchase with no trial',
    'There is no resettable free-minute or Capture allowance in this source',
    'qualifying original paid-app ownership remain valid',
    'you can read, search, copy, export, and delete existing history',
    'Subscriptions alone do not qualify for the discounted Family Lifetime upgrade',
    'Vox Android subscriptions are deferred and retain their existing offer',
    'StoreKit 2 weekly/yearly subscriptions, eligible 7-day trials, and lifetime purchases',
]:
    if required not in readme_source:
        errors.append(f'README subscription policy is missing {required!r}')
# The "Legacy quota provenance" section records the retired offer as history
# for the M0 baseline; only the rest of the README must stop advertising it.
readme_current_offer = readme_source.split('### Legacy quota provenance', 1)[0]
for retired_claim in [
    '15 minutes of free transcription',
    '10 successful Capture deliveries',
    'No subscription, no renewal',
    'StoreKit 2 one-time purchase',
]:
    if retired_claim in readme_current_offer:
        errors.append(f'README still advertises the retired free-allowance offer: {retired_claim!r}')

storekit_release_patch = (
    root / 'artifacts/releases/mac-family-restore-diagnostics.patch'
).read_text()
patched_paths = set(re.findall(r'^diff --git a/(.+?) b/', storekit_release_patch, flags=re.M))
expected_storekit_patch_paths = {
    'Packages/VoxboardShared/Sources/VoxboardShared/PurchaseAccess.swift',
    'Voxboard Mac/MacStoreManager.swift',
}
if patched_paths != expected_storekit_patch_paths:
    errors.append(
        f'independent Mac StoreKit patch changes {sorted(patched_paths)}, '
        f'expected only {sorted(expected_storekit_patch_paths)}'
    )

completion_audit_path = root / 'docs/recording-queue-storekit-completion-audit.md'
if not completion_audit_path.exists():
    errors.append('recording queue and StoreKit completion audit is missing')
else:
    completion_audit = completion_audit_path.read_text()
    for required in [
        'Overall status: **Not complete',
        '## Concrete objective',
        '## Requirement-to-artifact checklist',
        '## Constraint checklist',
        '## Verification surface',
        '## Unmet gates — completion is prohibited',
        'Physical-device recording matrix',
        'macOS signing and account matrix',
    ]:
        if required not in completion_audit:
            errors.append(f'completion audit is missing required gate {required}')
    for requirement_number in range(1, 11):
        if f'| {requirement_number} |' not in completion_audit:
            errors.append(f'completion audit does not map requirement {requirement_number}')

ios_runtime_evidence_path = root / 'artifacts/validation/ios-recording-queue-runtime-2026-08-11.md'
if not ios_runtime_evidence_path.exists():
    errors.append('iOS recording queue runtime evidence report is missing')
else:
    ios_runtime_evidence = ios_runtime_evidence_path.read_text()
    for required in [
        'Result: **PASS**',
        'Interrupted external WAV import',
        'Live claimed-job termination and relaunch recovery',
        'Runtime UI matrix',
        'adaptive two-column grid',
        'accessibility Dynamic Type sizes it switches to one column',
        'Vision OCR fails the harness',
        'does **not** claim to validate termination inside a production ASR backend',
        'does not cover physical microphone capture',
    ]:
        if required not in ios_runtime_evidence:
            errors.append(f'iOS runtime evidence is missing scope/evidence {required}')

ios_runtime_ui_paths = [
    root / 'artifacts/validation/ios-recording-queue-runtime-ui-failed-2026-08-11.png',
    root / 'artifacts/validation/ios-recording-queue-runtime-ui-failed-accessibility-2026-08-11.png',
    root / 'artifacts/validation/ios-recording-queue-runtime-ui-queued-2026-08-11.png',
    root / 'artifacts/validation/ios-recording-queue-runtime-ui-copy-2026-08-11.png',
]
for ios_runtime_ui_path in ios_runtime_ui_paths:
    if not ios_runtime_ui_path.exists():
        errors.append(f'iOS recording queue runtime UI evidence is missing: {ios_runtime_ui_path.name}')
        continue
    png = ios_runtime_ui_path.read_bytes()
    if len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n':
        errors.append(f'iOS recording queue runtime UI evidence is not a PNG: {ios_runtime_ui_path.name}')
    else:
        width, height = struct.unpack('>II', png[16:24])
        if width < 1_000 or height < 2_000:
            errors.append(
                f'iOS recording queue runtime UI evidence is too small: '
                f'{ios_runtime_ui_path.name} {width}x{height}'
            )

ios_runtime_test_path = root / 'scripts/test-ios-recording-queue-runtime.sh'
if not ios_runtime_test_path.exists():
    errors.append('isolated iOS recording queue runtime test is missing')
else:
    ios_runtime_test = ios_runtime_test_path.read_text()
    for required in [
        'simctl create',
        'simctl delete',
        'VOXBOARD_SHARED_CONTAINER_OVERRIDE',
        '--runtime-queue-validation --disable-release-notes',
        'recording_runtime_validation.wav',
        'VOXBOARD_IOS_RUNTIME_EVIDENCE_DIRECTORY',
        'content_size accessibility-extra-extra-large',
        'validate-recording-queue-screenshot.swift',
        '--runtime-queue-pause-after-claim',
        '--runtime-queue-activate-actions',
        'Runtime queue actions passed',
        'live claimed-job termination and relaunch recovery passed.',
        'queue action activation passed.',
        'Isolated iOS Simulator runtime queue validation passed.',
    ]:
        if required not in ios_runtime_test:
            errors.append(f'iOS queue runtime test is missing contract {required}')
    if not os.access(ios_runtime_test_path, os.X_OK):
        errors.append('iOS queue runtime test is not executable')

mac_runtime_evidence_path = root / 'artifacts/validation/mac-recording-queue-runtime-2026-08-11.md'
if not mac_runtime_evidence_path.exists():
    errors.append('macOS recording queue runtime evidence report is missing')
else:
    mac_runtime_evidence = mac_runtime_evidence_path.read_text()
    for required in [
        'Result: **PASS**',
        'Interrupted external WAV import',
        'Live claimed-job termination and relaunch recovery',
        'Two-process worker exclusion and failed-job retention',
        'Runtime UI rendering',
        'Vision OCR fails the harness',
        'Choose Preset, Reveal, Keep Audio, and Delete',
        'Process Now, Reveal, Keep Audio, and Delete',
        'completed deferred clipboard',
        'Copy, Reveal, Keep Audio, and Delete',
        'does **not** claim to validate termination inside a production ASR backend',
        'does not yet cover successful real microphone capture',
        'VOXBOARD_VALIDATE_REAL_MAC_MICROPHONE=1',
        'BLOCKED',
    ]:
        if required not in mac_runtime_evidence:
            errors.append(f'macOS runtime evidence is missing scope/evidence {required}')

mac_runtime_ui_paths = [
    root / 'artifacts/validation/mac-recording-queue-runtime-ui-2026-08-11.png',
    root / 'artifacts/validation/mac-recording-queue-runtime-ui-2026-08-11-queued.png',
    root / 'artifacts/validation/mac-recording-queue-runtime-ui-2026-08-11-copy.png',
]
for mac_runtime_ui_path in mac_runtime_ui_paths:
    if not mac_runtime_ui_path.exists():
        errors.append(f'macOS recording queue runtime UI evidence is missing: {mac_runtime_ui_path.name}')
        continue
    png = mac_runtime_ui_path.read_bytes()
    if len(png) < 24 or png[:8] != b'\x89PNG\r\n\x1a\n':
        errors.append(f'macOS recording queue runtime UI evidence is not a PNG: {mac_runtime_ui_path.name}')
    else:
        width, height = struct.unpack('>II', png[16:24])
        if width < 800 or height < 400:
            errors.append(
                f'macOS recording queue runtime UI evidence is too small: '
                f'{mac_runtime_ui_path.name} {width}x{height}'
            )

screenshot_validator_path = root / 'scripts/validate-recording-queue-screenshot.swift'
if not screenshot_validator_path.exists():
    errors.append('recording queue semantic screenshot validator is missing')
else:
    screenshot_validator = screenshot_validator_path.read_text()
    for required in [
        'VNRecognizeTextRequest',
        'ios-failed-accessibility',
        'ios-copy-ready',
        'mac-copy-ready',
        'Forbidden:',
    ]:
        if required not in screenshot_validator:
            errors.append(f'recording queue screenshot validator is missing {required}')
    if not os.access(screenshot_validator_path, os.X_OK):
        errors.append('recording queue screenshot validator is not executable')

mac_runtime_test_path = root / 'scripts/test-mac-recording-queue-runtime.sh'
if not mac_runtime_test_path.exists():
    errors.append('isolated macOS recording queue runtime test is missing')
else:
    mac_runtime_test = mac_runtime_test_path.read_text()
    for required in [
        'VOXBOARD_SHARED_CONTAINER_OVERRIDE',
        '--runtime-queue-validation',
        'recording_runtime_validation.wav',
        'VOXBOARD_RUNTIME_SCREENSHOT_OUTPUT',
        '--localization-screenshot 06-recording-queue',
        'COPY_SCREENSHOT_OUTPUT',
        'validate-recording-queue-screenshot.swift',
        '"delivery"] = {"clipboard": {}}',
        '--runtime-queue-pause-after-claim',
        'Isolated macOS live claimed-job termination and relaunch recovery passed.',
        'Isolated macOS two-process worker lease passed.',
        'VOXBOARD_VALIDATE_REAL_MAC_MICROPHONE',
        'codesign --force --deep --sign -',
        'runtime-microphone.entitlements',
        'com.apple.security.device.audio-input',
        '--runtime-microphone-capture',
        'Isolated real macOS microphone capture and durable queue handoff passed.',
        'RUNTIME_ROOT="$(mktemp -d "$RUNTIME_PARENT/mac.XXXXXX")"',
        'realpath "$RUNTIME_ROOT"',
        'Refusing symlinked runtime validation parent',
        'attemptCount',
    ]:
        if required not in mac_runtime_test:
            errors.append(f'macOS queue runtime test is missing contract {required}')
    if not os.access(mac_runtime_test_path, os.X_OK):
        errors.append('macOS queue runtime test is not executable')
    if 'VOXBOARD_MAC_APP' in mac_runtime_test:
        errors.append('macOS queue runtime test must not accept caller-supplied apps')

app_constants_source = (root / 'Packages/VoxboardShared/Sources/VoxboardShared/AppConstants.swift').read_text()
ios_app_source = (root / 'Voxboard/VoxboardApp.swift').read_text()
ios_recorder_source = (root / 'Voxboard/PersistentRecorder.swift').read_text()
mac_app_source = (root / 'Voxboard Mac/VoxboardMacApp.swift').read_text()
mac_recorder_source = (root / 'Voxboard Mac/MacRecorder.swift').read_text()
debug_hook_contracts = [
    (
        'AppConstants',
        app_constants_source,
        '#if DEBUG\n    public static let debugSharedContainerOverrideEnvironmentKey =',
        '"VOXBOARD_SHARED_CONTAINER_OVERRIDE"',
        'environment[debugSharedContainerOverrideEnvironmentKey]',
    ),
    (
        'VoxboardApp',
        ios_app_source,
        '#if DEBUG\n    private static let runtimeQueueValidationArgument =',
        '"--runtime-queue-validation"',
        'arguments.contains(Self.runtimeQueueValidationArgument)',
    ),
    (
        'PersistentRecorder',
        ios_recorder_source,
        '#if DEBUG\n    private static let runtimeQueuePauseAfterClaimArgument =',
        '"--runtime-queue-pause-after-claim"',
        'arguments.contains(\n                PersistentRecorder.runtimeQueuePauseAfterClaimArgument',
    ),
    (
        'VoxboardMacApp',
        mac_app_source,
        '#if DEBUG\n    private static let runtimeQueueValidationArgument =',
        '"--runtime-queue-validation"',
        'arguments.contains(Self.runtimeQueueValidationArgument)',
    ),
    (
        'MacRecorder',
        mac_recorder_source,
        '#if DEBUG\n    private static let runtimeQueuePauseAfterClaimArgument =',
        '"--runtime-queue-pause-after-claim"',
        'arguments.contains(\n                MacRecorder.runtimeQueuePauseAfterClaimArgument',
    ),
    (
        'MacRecorder microphone',
        mac_recorder_source,
        'private static let runtimeMicrophoneCaptureArgument =',
        '"--runtime-microphone-capture"',
        'arguments.contains(Self.runtimeMicrophoneCaptureArgument)',
    ),
]
for source_name, source, declaration, raw_value, use in debug_hook_contracts:
    if declaration not in source or use not in source or source.count(raw_value) != 1:
        errors.append(
            f'{source_name} runtime validation value must be declared only inside DEBUG '
            'and referenced through that unavailable-in-Release symbol'
        )

recording_queue_views = (root / 'Voxboard App Shared/RecordingQueueViews.swift').read_text()
action_debug_match = re.search(
    r'#if DEBUG\n(?P<body>.*?)\n    #endif\n\n    private func retryAllFailedJobs',
    recording_queue_views,
    flags=re.S,
)
if action_debug_match is None:
    errors.append('recording queue action validation task and method must share one DEBUG block')
else:
    action_debug_body = action_debug_match.group('body')
    required_guard = '''guard processInfo.arguments.contains("--runtime-queue-validation"),
                  processInfo.arguments.contains("--runtime-queue-activate-actions"),
                  let overridePath = processInfo.environment[
                    AppConstants.debugSharedContainerOverrideEnvironmentKey
                  ],
                  !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let overrideURL = Optional(
                    URL(fileURLWithPath: overridePath, isDirectory: true)
                        .standardizedFileURL
                  ),
                  overrideURL.path.hasPrefix(
                    URL(
                        fileURLWithPath: "/tmp/VoxQueueRuntimeValidation",
                        isDirectory: true
                    ).standardizedFileURL.path + "/"
                  ),
                  AppConstants.sharedContainerURL?.standardizedFileURL.path
                    == overrideURL.path else { return }'''
    for required in [
        required_guard,
        '.task {',
        'private func activateRuntimeValidationActions(',
        'private func activateExtendedRuntimeValidationActions()',
        '"--runtime-queue-activate-extended-actions"',
        'await queue.retry(failed)',
        'await queue.processNow(queued)',
        'await queue.updateRetention(queued, policy: .permanent)',
        'await queue.acknowledgeCopiedResult(copyReady)',
        'await queue.discard(currentQueued)',
        'let retryAllJobs = queue.retryAllEligibleJobs.filter {',
        '"runtime-retry-one.wav"',
        '"runtime-retry-two.wav"',
        '$0.originalFilename.map(retryFilenames.contains) == true',
        '$0.originalFilename == "runtime-timed.wav"',
        '$0.originalFilename == "runtime-delete-after.wav"',
        'await queue.updateRetention(\n            timed,\n            policy: .timed(',
        'await queue.updateRetention(\n            deleteAfterSuccess,\n            policy: .deleteAfterSuccess',
    ]:
        if required not in action_debug_body:
            errors.append(
                f'recording queue action validation DEBUG/isolation block is missing {required}'
            )
if recording_queue_views.count('"--runtime-queue-activate-actions"') != 1:
    errors.append('recording queue action activation argument must appear once inside its DEBUG hook')

ios_runtime_harness = (root / 'scripts/test-ios-recording-queue-runtime.sh').read_text()
for required in [
    'expected.write_text(json.dumps(created_ids, indent=2, sort_keys=True))',
    'set(retry_ids) != {expected["retry-one"], expected["retry-two"]}',
    'retention_ids != [expected["timed"], expected["delete-after"]]',
]:
    if required not in ios_runtime_harness:
        errors.append(f'iOS extended action harness is missing exact fixture-ID check {required}')

# Recording queue card actions. macOS keeps a full action row; iOS shows one
# primary pill (failed: "Retry"), an optional Copy Transcript pill and a •••
# menu holding Share Audio, Keep Audio and Delete Recording. Every action stays
# reachable and Delete Recording is always confirmed before discarding.
for required in [
    '.navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)',
]:
    if required not in recording_queue_views:
        errors.append(f'recording queue layout is missing {required}')
queue_row_start = recording_queue_views.find('private struct RecordingQueueRow: View {')
queue_row_end = recording_queue_views.find('\nstruct ', queue_row_start + 1)
queue_row = recording_queue_views[queue_row_start:queue_row_end] if queue_row_start >= 0 else ''
if not queue_row:
    errors.append('recording queue row (RecordingQueueRow) is missing')
action_area_start = queue_row.find('private var actionArea: some View {')
action_area_end = queue_row.find('    #if !os(macOS)\n    @ViewBuilder\n    private var compactActions', action_area_start)
action_area = queue_row[action_area_start:action_area_end] if action_area_start >= 0 and action_area_end > action_area_start else ''
for required in [
    '#if os(macOS)\n            HStack(spacing: 12) {\n                applicableActions\n                Spacer()\n                deleteAction\n            }',
    'if dynamicTypeSize.isAccessibilitySize {\n                VStack(alignment: .leading, spacing: Geist.Spacing.two) { compactActions }\n            } else {\n                HStack(spacing: Geist.Spacing.two) { compactActions }\n            }',
    '.confirmationDialog(\n            String(localized: "Delete this recording?"),\n            isPresented: $confirmsDelete,',
    'Button("Delete Recording", role: .destructive) {\n                Task { await queue.discard(job) }\n            }',
    'Button("Cancel", role: .cancel) {}',
    'Text("The audio and any transcript are removed from this Mac. This can’t be undone.")',
    'Text("The audio and any transcript are removed from this iPhone. This can’t be undone.")',
]:
    if required not in action_area:
        errors.append(f'recording queue action area is missing {required}')
if action_area.find('.confirmationDialog(') < action_area.find('#endif'):
    errors.append('recording queue Delete Recording confirmation must cover both macOS and iOS layouts')
if queue_row.count('await queue.discard(job)') != 1 or 'await queue.discard(job)' not in action_area:
    errors.append('recording queue rows may discard a recording only from the Delete Recording confirmation')
if '@State private var confirmsDelete = false' not in queue_row:
    errors.append('recording queue row must own its Delete Recording confirmation state')

compact_start = queue_row.find('private var compactActions: some View {')
compact_end = queue_row.find('    #endif', compact_start)
compact_actions = queue_row[compact_start:compact_end] if compact_start >= 0 else ''
if not compact_actions:
    errors.append('iOS recording queue compact actions are missing')
for required in [
    'primaryAction',
    'Button("Copy Transcript", systemImage: "doc.on.doc")',
    'await queue.acknowledgeCopiedResult(job)',
    'Menu {',
    'ShareLink(item: audioURL) {\n                    Label("Share Audio", systemImage: "square.and.arrow.up")',
    'keepAudioMenu',
    'if job.phase != .processing && job.phase != .finalizing {',
    'Button("Delete Recording", systemImage: "trash", role: .destructive) {\n                    confirmsDelete = true\n                }',
    'Label("More options", systemImage: "ellipsis")',
    '.accessibilityLabel("More options")',
]:
    if required not in compact_actions:
        errors.append(f'iOS recording queue ••• actions are missing {required}')
for forbidden in ['LazyVGrid(', 'GridItem(']:
    if forbidden in compact_actions:
        errors.append(f'iOS recording queue actions must not return to the 2×2 grid: {forbidden}')

delete_action_start = queue_row.find('private var deleteAction: some View {')
delete_action = queue_row[delete_action_start:queue_row.find('    @ViewBuilder', delete_action_start)]
if 'confirmsDelete = true' not in delete_action or 'discard' in delete_action:
    errors.append('macOS recording queue Delete Recording must ask for confirmation first')

keep_audio_start = queue_row.find('private var keepAudioMenu: some View {')
keep_audio = queue_row[keep_audio_start:queue_row.find('    @ViewBuilder', keep_audio_start)]
for required in [
    'policy: .deleteAfterSuccess',
    'policy: .timed(interval)',
    'policy: .permanent',
]:
    if required not in keep_audio:
        errors.append(f'recording queue Keep Audio menu is missing {required}')

primary_start = queue_row.find('private var primaryAction: some View {')
primary_action = queue_row[primary_start:queue_row.find('    @ViewBuilder', primary_start)]
for required in [
    'Button("Process Now", systemImage: "play.fill")',
    'Menu("Choose Route", systemImage: "arrow.triangle.branch")',
    'await retryCoordinator.retry(job)',
    'await queue.retry(job)',
    'Text("Retry")',
    'Label("Retry Recording", systemImage: "arrow.clockwise")',
    '.accessibilityLabel("Retry Recording")',
]:
    if required not in primary_action:
        errors.append(f'recording queue failed-card Retry pill is missing {required}')

storekit_preflight_path = root / 'scripts/preflight-mac-family-restore-release.sh'
if not storekit_preflight_path.exists():
    errors.append('independent Mac StoreKit release preflight script is missing')
else:
    storekit_preflight = storekit_preflight_path.read_text()
    for required in [
        'mac-family-restore-diagnostics.patch',
        'CODE_SIGNING_ALLOWED=NO',
        'asc iap list',
        'asc builds list',
        'Apple Distribution',
        'no local provisioning profile',
        'Release upload is intentionally not attempted',
        'Never feed an untrusted or stale patch into a build',
        'set +e',
    ]:
        if required not in storekit_preflight:
            errors.append(f'Mac StoreKit preflight is missing safety contract {required}')
    for forbidden in ['asc builds upload', 'asc publish', '--confirm', 'git worktree prune']:
        if forbidden in storekit_preflight:
            errors.append(f'Mac StoreKit preflight must remain read-only: {forbidden}')
    if not os.access(storekit_preflight_path, os.X_OK):
        errors.append('Mac StoreKit preflight script is not executable')

widget_bundle_id = 'bontecou.Voxboard.Voxboard-Widget'
blocks = [
    pbx_settings_text(settings)
    for name, settings in build_configurations
    if name in ('Debug', 'Release')
]
widget_blocks = [
    pbx_settings_text(settings)
    for name, settings in build_configurations
    if name in ('Debug', 'Release') and settings.get('PRODUCT_BUNDLE_IDENTIFIER') == widget_bundle_id
]
if len(widget_blocks) != 2:
    errors.append(f'expected 2 widget build configurations, found {len(widget_blocks)}')

expected_entitlements = 'CODE_SIGN_ENTITLEMENTS = "Voxboard Widget/VoxboardWidget.entitlements";'
for index, body in enumerate(widget_blocks, start=1):
    if expected_entitlements not in body:
        errors.append(f'widget configuration {index} does not use VoxboardWidget.entitlements')
    match = re.search(r'IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);', body)
    if match is None:
        errors.append(f'widget configuration {index} has no explicit iOS deployment target')
    elif match.group(1).strip() != '17.6':
        errors.append(
            f'widget configuration {index} deployment target is {match.group(1).strip()}, expected 17.6'
        )

if 'CODE_SIGN_ENTITLEMENTS = "Voxboard WidgetExtension.entitlements";' in project:
    errors.append('widget target still references the legacy root entitlement file')
legacy_widget_entitlements = root / 'Voxboard WidgetExtension.entitlements'
if legacy_widget_entitlements.exists():
    errors.append('legacy root widget entitlement file still exists')
if '/* Voxboard WidgetExtension.entitlements */' in project:
    errors.append('Xcode project still contains the legacy widget entitlement file reference')

expected_group = 'group.bontecou.Voxboard'
entitlement_paths = [
    root / 'Voxboard/Voxboard.entitlements',
    root / 'Voxboard Keyboard/VoxboardKeyboard.entitlements',
    root / 'Voxboard Widget/VoxboardWidget.entitlements',
    root / 'Voxboard Share Extension/VoxboardShare.entitlements',
    root / 'Voxboard Mac/VoxboardMac.entitlements',
]
for path in entitlement_paths:
    content = path.read_text()
    if expected_group not in content:
        errors.append(f'{path.relative_to(root)} does not use {expected_group}')
    if 'group.bontecou.VoxVault' in content:
        errors.append(f'{path.relative_to(root)} still uses the legacy VoxVault App Group')

mac_entitlements = (root / 'Voxboard Mac/VoxboardMac.entitlements').read_text()
if not re.search(
    r'<key>\s*com\.apple\.security\.network\.client\s*</key>\s*<true\s*/>',
    mac_entitlements,
):
    errors.append('macOS app must allow outgoing network connections for model downloads')

main_target_matches = [
    settings.get('IPHONEOS_DEPLOYMENT_TARGET')
    for name, settings in build_configurations
    if settings.get('PRODUCT_BUNDLE_IDENTIFIER') == 'bontecou.Voxboard'
    and settings.get('SDKROOT') != 'macosx'
]
if sorted(
    name for name, settings in build_configurations
    if settings.get('PRODUCT_BUNDLE_IDENTIFIER') == 'bontecou.Voxboard' and settings.get('SDKROOT') != 'macosx'
) != ['Debug', 'Release'] or any(value != '17.6' for value in main_target_matches):
    errors.append('main app deployment target contract is not iOS 17.6')

share_bundle_id = 'bontecou.Voxboard.ShareExtension'
share_blocks = [
    pbx_settings_text(settings)
    for name, settings in build_configurations
    if name in ('Debug', 'Release') and settings.get('PRODUCT_BUNDLE_IDENTIFIER') == share_bundle_id
]
if len(share_blocks) != 2:
    errors.append(f'expected 2 share-extension build configurations, found {len(share_blocks)}')
for index, body in enumerate(share_blocks, start=1):
    if 'CODE_SIGN_ENTITLEMENTS = "Voxboard Share Extension/VoxboardShare.entitlements";' not in body:
        errors.append(f'share configuration {index} does not use the shared App Group entitlement')
    if 'INFOPLIST_FILE = "Voxboard Share Extension/Info.plist";' not in body:
        errors.append(f'share configuration {index} does not use the checked-in extension Info.plist')
    if 'IPHONEOS_DEPLOYMENT_TARGET = 17.6;' not in body:
        errors.append(f'share configuration {index} deployment target is not 17.6')

if 'Voxboard Share Extension.appex in Embed Foundation Extensions' not in project:
    errors.append('main app does not embed the share extension')
if 'productName = VoxboardCaptureCore;' not in project:
    errors.append('share extension is not linked to the capture core package product')

share_info = (root / 'Voxboard Share Extension/Info.plist').read_text()
for required in [
    'com.apple.share-services',
    'NSExtensionActivationSupportsText',
    'NSExtensionActivationSupportsWebURLWithMaxCount',
    'NSExtensionActivationSupportsImageWithMaxCount',
    'NSExtensionActivationSupportsFileWithMaxCount',
]:
    if required not in share_info:
        errors.append(f'share extension Info.plist is missing {required}')

main_info = (root / 'Voxboard/Info.plist').read_text()
for required in [
    'NSCameraUsageDescription',
    'NSPhotoLibraryUsageDescription',
    'NSMicrophoneUsageDescription',
    'NSLocationWhenInUseUsageDescription',
]:
    if required not in main_info:
        errors.append(f'main app Info.plist is missing {required}')

location_purpose_contracts = [
    (
        root / 'Voxboard/Info.plist',
        root / 'Voxboard/InfoPlist.xcstrings',
        'NSLocationWhenInUseUsageDescription',
        'Vox.md gets your location once when you insert a map link, or when you send or stop recording with a location-enabled Route.',
    ),
    (
        root / 'Voxboard Share Extension/Info.plist',
        root / 'Voxboard Share Extension/InfoPlist.xcstrings',
        'NSLocationWhenInUseUsageDescription',
        'When location metadata is enabled for a Route, Vox.md gets one location when you send shared content.',
    ),
    (
        root / 'Voxboard Watch/Info.plist',
        root / 'Voxboard Watch/InfoPlist.xcstrings',
        'NSLocationWhenInUseUsageDescription',
        'When location is enabled for a Route, Vox.md gets one location from this Apple Watch when recording stops.',
    ),
    (
        root / 'Voxboard Mac/Info.plist',
        root / 'Voxboard Mac/InfoPlist.xcstrings',
        'NSLocationUsageDescription',
        'When location is enabled for a Route, Vox.md gets one location when you send or stop a recording.',
    ),
]
expected_location_locales = {
    'ar', 'bn', 'de', 'en', 'es', 'fr', 'hi', 'id', 'it', 'ja', 'ko', 'nl',
    'pl', 'pt-BR', 'ru', 'ta', 'th', 'tr', 'uk', 'ur', 'vi', 'zh-Hans', 'zh-Hant',
}
for plist_path, catalog_path, key, english_value in location_purpose_contracts:
    plist = plist_path.read_text()
    if key not in plist or f'<string>{english_value}</string>' not in plist:
        errors.append(f'{plist_path.relative_to(root)} has stale location purpose copy')
    catalog = json.loads(catalog_path.read_text())
    entry = catalog.get('strings', {}).get(key, {})
    localizations = entry.get('localizations', {})
    if set(localizations) != expected_location_locales:
        errors.append(f'{catalog_path.relative_to(root)} lacks complete location purpose locale coverage')
    english_unit = localizations.get('en', {}).get('stringUnit', {})
    if english_unit.get('value') != english_value:
        errors.append(f'{catalog_path.relative_to(root)} location purpose English does not match Info.plist')
    untranslated = [
        locale for locale, value in localizations.items()
        if locale != 'en' and value.get('stringUnit', {}).get('value') == english_value
    ]
    if untranslated:
        errors.append(
            f'{catalog_path.relative_to(root)} labels English location purpose copy as translated: {untranslated}'
        )

widget_bundle = (root / 'Voxboard Widget/VoxboardWidgetBundle.swift').read_text()
if 'VoxboardCaptureWidget()' not in widget_bundle:
    errors.append('widget bundle does not expose the Quick Capture widget')

capture_widget = (root / 'Voxboard Widget/VoxboardCaptureWidget.swift').read_text()
for required in [
    '.systemMedium',
    '.systemLarge',
    'captureURL(action: "photos")',
    'captureURL(action: "camera")',
    'captureURL(action: "files")',
    'captureURL(action: "link")',
    'captureURL(action: "scan")',
    'captureURL(action: "sketch")',
    'captureURL(action: "screenshots")',
    'captureURL(action: "voice")',
]:
    if required not in capture_widget:
        errors.append(f'Quick Capture widget is missing actionable contract {required}')

app_source = (root / 'Voxboard/VoxboardApp.swift').read_text()
if 'url.absoluteString' in app_source:
    errors.append('app URL handling can persist private deep-link query values')

root_view_source = (root / 'Voxboard/Views/RootView.swift').read_text()
if re.search(r'case[^\n]*\blisten\b', root_view_source) or 'case .listen:' in root_view_source:
    errors.append('Listen must not remain a top-level app destination')
for required in [
    'case capture',
    'case settings',
    'persistentRecorder: persistentRecorder',
    'pendingKeyboardLaunch: $pendingKeyboardLaunch',
]:
    if required not in root_view_source:
        errors.append(f'inline Capture recording integration is missing {required}')
for removed_destination in ['case .model:', 'case .presets:', 'case .vox:', 'tab_model', 'tab_presets', 'tab_vox']:
    if removed_destination in root_view_source:
        errors.append(f'Models and Capture Presets must live under Settings, not app navigation: {removed_destination}')
settings_source = (root / 'Voxboard/Views/MetaSettingsView.swift').read_text()
for required in ['customizationSection', 'ModelTabView()', 'CapturePresetSettingsView()']:
    if required not in settings_source:
        errors.append(f'Settings customization navigation is missing {required}')
flow_settings_source = (root / 'Voxboard/Views/FlowSettingsView.swift').read_text()
recording_only_settings_gate = '''            if flow.watchOutputMode != .recordingOnly {
                voiceProcessingSection
                postProcessingSection
                ownedDestinationSection
                if flow.captureDestinationID == nil {
                    fileExportSection
                }
                urlDeliverySection
                if showsFrontmatterSection {
                    frontmatterSection
                    locationMetadataSection
                }
                audioExportSection
            }'''
if re.sub(r'\n\s+', '\n', recording_only_settings_gate.strip()) not in re.sub(r'\n\s+', '\n', flow_settings_source):
    errors.append('Recording Only Apple Watch presets must hide transcript workflow settings')
if (root / 'Voxboard/Views/HomeView.swift').exists():
    errors.append('the standalone Home/Listen recording view must be removed')
if (root / 'Voxboard/Views/CaptureHistoryView.swift').exists():
    errors.append('the separate Capture history view must be removed in favor of unified history')
for required in ['case "listen":', 'rootDestination = .capture', 'pendingKeyboardLaunch = true']:
    if required not in app_source:
        errors.append(f'legacy recording launch routing is missing {required}')

# Custom onboarding analytics is retired: no client, transport, endpoint
# configuration, or producer may remain in any shipped target, upgrades must erase
# the retired local state, and the endpoint only discards legacy uploads.
retired_analytics_directory = root / 'Packages/VoxboardShared/Sources/VoxboardShared/Analytics'
if retired_analytics_directory.is_dir() and any(p.is_file() for p in retired_analytics_directory.rglob('*')):
    errors.append('retired onboarding analytics sources must be absent')
retired_analytics_pattern = re.compile(
    r'OnboardingAnalytics|PricingAnalytics|Cloudflare(?:Onboarding|Pricing)AnalyticsTransport'
    r'|ONBOARDING_ANALYTICS|PRICING_ANALYTICS|trackOnboarding|claimOneShotAnalyticsMarker'
    r'|AAAttribution|AppleAdsAttribution|/v1/events'
)
retired_analytics_cleanup_path = 'Packages/VoxboardShared/Sources/VoxboardShared/RetiredAnalyticsCleanup.swift'
for target in [
    'Voxboard', 'Voxboard Mac', 'Voxboard App Shared', 'Voxboard Keyboard', 'Voxboard Widget',
    'Voxboard Share Extension', 'Voxboard Watch', 'Voxboard Watch Shared', 'Voxboard Watch Widget',
    'Packages/VoxboardShared/Sources',
]:
    for path in sorted((root / target).rglob('*')):
        if path.suffix not in ('.swift', '.plist', '.xcconfig', '.entitlements') or not path.is_file():
            continue
        if path.relative_to(root).as_posix() == retired_analytics_cleanup_path:
            continue
        match = retired_analytics_pattern.search(path.read_text(errors='ignore'))
        if match:
            errors.append(f'retired analytics reference {match.group(0)!r} remains in {path.relative_to(root)}')
match = retired_analytics_pattern.search(project)
if match:
    errors.append(f'Xcode project still configures retired analytics: {match.group(0)!r}')
retired_analytics_cleanup = (root / retired_analytics_cleanup_path).read_text()
retired_analytics_keys = {
    'onboarding.analytics.install_id.v1',
    'onboarding.analytics.queue.v1',
    'onboarding.experiment.assignment.v1',
    'onboarding.analytics.started.v1',
    'onboarding.analytics.model_setup_completed.v1',
    'onboarding.analytics.completed.v1',
}
if set(re.findall(r'"(onboarding\.[^"\n]+)"', retired_analytics_cleanup)) != retired_analytics_keys:
    errors.append('RetiredAnalyticsCleanup must erase exactly the retired onboarding analytics keys')
if 'defaults.removeObject(forKey: key)' not in retired_analytics_cleanup:
    errors.append('RetiredAnalyticsCleanup must remove each retired key')
for forbidden in ('URLSession', 'URLRequest', 'UUID()', 'defaults.set('):
    if forbidden in retired_analytics_cleanup:
        errors.append(f'RetiredAnalyticsCleanup must not create identifiers, write state, or send requests: {forbidden}')
for launch_path in ['Voxboard/VoxboardApp.swift', 'Voxboard Mac/VoxboardMacApp.swift']:
    launch_source = (root / launch_path).read_text()
    for required in [
        'RetiredAnalyticsCleanup.run()',
        'if let defaults = AppConstants.sharedDefaults { RetiredAnalyticsCleanup.run(defaults: defaults) }',
    ]:
        if required not in launch_source:
            errors.append(f'{launch_path} must erase retired analytics state at launch: {required}')
retired_worker = root / 'worker/onboarding-analytics'
retired_worker_source = (retired_worker / 'src/index.ts').read_text()
for required in [
    'return Response.json({ status: "retired", collection: false }, { headers });',
    'return new Response(null, { status: 410, headers });',
]:
    if required not in retired_worker_source:
        errors.append(f'retired analytics endpoint is missing {required}')
for forbidden in ['request.json(', 'request.text(', 'request.arrayBuffer(', 'env.', 'fetch(env', 'console.']:
    if forbidden in retired_worker_source:
        errors.append(f'retired analytics endpoint must not read bodies, bindings, or log: {forbidden}')
if not (retired_worker / 'test/retired-analytics.test.mjs').is_file():
    errors.append('retired analytics endpoint test is missing')
if (retired_worker / 'test/onboarding-analytics.test.mjs').exists():
    errors.append('the collecting onboarding analytics endpoint test must be removed')

share_source = (root / 'Voxboard Share Extension/ShareViewController.swift').read_text()
for required in [
    'CaptureInputBudget()',
    'reserveSharedItems(providers.count)',
    'reserveText(characters:',
    'reserveAsset(bytes:',
    'removeStagingDirectory()',
    'isQueuedForLater',
    'cancellationRequested',
    '.disabled(model.isQueuedForLater)',
]:
    if required not in share_source:
        errors.append(f'share extension hardening is missing {required}')
if 'providers.prefix(' in share_source:
    errors.append('share extension silently truncates shared providers instead of rejecting overflow')

quick_capture_source = (root / 'Voxboard/Views/QuickCaptureView.swift').read_text()
multimodal_capture_source = (root / 'Voxboard/Capture/MultimodalCaptureViews.swift').read_text()
watch_queue_source = (root / 'Voxboard/Views/WatchRecordingQueueView.swift').read_text()
capture_canvas_source = (root / 'Voxboard/Capture/QuickCaptureCanvas.swift').read_text()
quick_capture_ui_source = quick_capture_source + capture_canvas_source + multimodal_capture_source + watch_queue_source
watch_bridge_source = (root / 'Voxboard Watch Shared/WatchPhoneBridge.swift').read_text()
watch_controller_source = (root / 'Voxboard/WatchRecordingController.swift').read_text()
watch_pipeline_source = (root / 'Voxboard/WatchRecordingPipeline.swift').read_text()
watch_inbox_source = (root / 'Voxboard/WatchRecordingInbox.swift').read_text()
watch_background_lease_source = (root / 'Voxboard/WatchRecordingBackgroundLease.swift').read_text()
watch_background_tests_source = (root / 'VoxboardTests/WatchRecordingBackgroundLeaseTests.swift').read_text()
watch_app_delegate_source = (root / 'Voxboard/VoxboardAppDelegate.swift').read_text()
watch_recorder_source = (root / 'Voxboard Watch/WatchLocalRecorder.swift').read_text()
watch_queue_store_source = (
    root / 'Voxboard Watch Shared/WatchLocalRecordingQueueStore.swift'
).read_text()
watch_view_source = (root / 'Voxboard Watch/WatchRecorderView.swift').read_text()

watch_receive_marker = 'nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile)'
watch_receive_start = watch_controller_source.find(watch_receive_marker)
watch_receive_end = watch_controller_source.find('\n}\n\nnonisolated enum WatchRecordingPayloadKey', watch_receive_start)
if watch_receive_start < 0 or watch_receive_end < 0:
    errors.append('iPhone Watch file receive callback could not be inspected')
else:
    watch_receive_source = watch_controller_source[watch_receive_start:watch_receive_end]
    lease_begin = watch_receive_source.find('WatchRecordingBackgroundLease.begin(')
    inbox_enqueue = watch_receive_source.find('WatchRecordingInbox.shared.enqueue(')
    main_actor_handoff = watch_receive_source.find('Task { @MainActor')
    if lease_begin < 0 or inbox_enqueue < 0 or lease_begin >= inbox_enqueue:
        errors.append('Watch file receive must acquire its background lease before durable inbox enqueue')
    if main_actor_handoff < 0 or main_actor_handoff <= inbox_enqueue:
        errors.append('Watch file receive must enqueue synchronously before its MainActor handoff')
    for required in [
        'backgroundLease.end(.enqueueFailed)',
        'backgroundLease.end(.pipelineUnavailable)',
        'pipeline.recordingDidArrive(',
        'backgroundLease: backgroundLease',
    ]:
        if required not in watch_receive_source:
            errors.append(f'Watch file receive background lease handoff is missing {required}')

for required in [
    'activeBackgroundLease',
    'pendingBackgroundLease',
    'func backgroundLeaseDidExpire(_ token: UUID)',
    'processingTask?.cancel()',
    'completedLease?.end(.completed)',
    'WatchRecordingBackgroundExecutionPolicy.shouldStart(',
]:
    if required not in watch_pipeline_source:
        errors.append(f'Watch background pipeline ownership is missing {required}')
if 'beginBackgroundTaskIfNeeded' in watch_pipeline_source:
    errors.append('Watch pipeline must not retain the old late background-task acquisition path')
if '@UIApplicationDelegateAdaptor(VoxboardAppDelegate.self)' not in app_source:
    errors.append('iOS must install its WatchConnectivity application delegate before scene presentation')
for required in [
    'didFinishLaunchingWithOptions',
    'WatchRecordingController.shared.activateForBackgroundDelivery()',
]:
    if required not in watch_app_delegate_source:
        errors.append(f'iOS background WatchConnectivity launch hook is missing {required}')
if 'func activateForBackgroundDelivery()' not in watch_controller_source:
    errors.append('Watch controller must expose early application-delegate activation')
for required in [
    'private func wakeCompanionForQueuedRecording(using session: WCSession)',
    'session.sendMessage(payload)',
    'wakeCompanionForQueuedRecording(using: session)',
]:
    if required not in watch_bridge_source:
        errors.append(f'Watch completed-file wake hint is missing {required}')
if 'Open Vox.md to review a Watch recording delivery problem.' not in watch_pipeline_source:
    errors.append('Watch recording failure notifications must use privacy-safe generic copy')
if 'content.body = message' in watch_pipeline_source:
    errors.append('Watch recording failure notifications must not expose folder/provider errors')
for required in [
    'nonisolated final class WatchRecordingBackgroundLease',
    'private let lock = NSLock()',
    'case expired',
    'expirationCallback(token)',
    'service.end(identifier)',
]:
    if required not in watch_background_lease_source:
        errors.append(f'Watch background lease safety is missing {required}')
watch_sidecar_write = watch_inbox_source.find('try saveSidecarUnlocked(newItem)')
watch_durable_move = watch_inbox_source.rfind('try FileManager.default.moveItem(at: fileURL, to: destination)')
if watch_sidecar_write < 0 or watch_durable_move < 0 or watch_sidecar_write >= watch_durable_move:
    errors.append('Watch inbox must journal metadata before moving the temporary WCSession file')
watch_filename_reservation = watch_pipeline_source.find('updated.reservedOutputFilename = reservedFilename')
watch_files_copy = watch_pipeline_source.find('try exporter.copy(')
if watch_filename_reservation < 0 or watch_files_copy < 0 or watch_filename_reservation >= watch_files_copy:
    errors.append('Recording Only delivery must persist its filename reservation before copying to Files')
if 'force-quitting Vox.md prevents background delivery' not in flow_settings_source:
    errors.append('Recording Only settings must disclose force-quit background delivery limits')
for required in [
    'testExpirationDuringBeginEndsReturnedIdentifier',
    'testInvalidIdentifierNeverAttemptsUIKitEnd',
    'testBackgroundExecutionPolicyRequiresForegroundOrActiveLease',
    'testRecordingOnlyPipelineCopiesQueuedWatchFileWithoutUIResume',
]:
    if required not in watch_background_tests_source:
        errors.append(f'Watch background delivery test coverage is missing {required}')
if not (root / 'Voxboard.xcodeproj/xcshareddata/xcschemes/VoxboardTests.xcscheme').exists():
    errors.append('Watch background delivery tests must have a shared Xcode scheme')
for protocol_key in [
    'presetSummaries',
    'presetSelectionAvailable',
    'requestedPresetID',
    'presetSelectionRequestID',
    'presetSelectionEpoch',
    'presetSelectionSequence',
    'presetSelectionResult',
    'stateEpoch',
]:
    declaration = f'static let {protocol_key} = "{protocol_key}"'
    if declaration not in watch_bridge_source or declaration not in watch_controller_source:
        errors.append(f'Watch preset protocol key is not mirrored by Watch and iPhone: {protocol_key}')
for source_name, source in [
    ('Watch bridge', watch_bridge_source),
    ('iPhone Watch controller', watch_controller_source),
]:
    if 'case selectPreset' not in source:
        errors.append(f'{source_name} is missing the selectPreset command')
for required in [
    'WatchConfirmedPresetStore',
    'PendingWatchPresetSelection',
    'remoteSnapshotIsCurrent',
    'resendPendingPresetSelectionIfNeeded',
]:
    if required not in watch_bridge_source:
        errors.append(f'Watch preset selection safety is missing {required}')
for required in [
    'let epoch: Int64',
    'let sequence: Int64',
    'Int64(now.timeIntervalSince1970 * 1_000)',
]:
    if required not in watch_bridge_source:
        errors.append(f'Watch preset counters must remain arm64_32-safe: {required}')
if 'Int(Date().timeIntervalSince1970 * 1_000)' in watch_bridge_source:
    errors.append('Watch preset epoch overflows 32-bit Int on physical Watch hardware')
for required in [
    'WatchLocalRecordingQueueStore',
    'loadRecoveringInterruptedCapture',
    'saveActiveRecording',
    'index-corrupt-',
]:
    if required not in watch_queue_store_source:
        errors.append(f'Watch queue compatibility store is missing {required}')
if 'typealias QueuedRecording = WatchLocalQueuedRecording' not in watch_recorder_source:
    errors.append('Watch recorder is not consuming the compatibility queue model')

for required in [
    'hasPresetSelectionAvailabilityPayload',
    # Each Watch recording must carry its exact Route snapshot when iPhone
    # advertises Route selection; arrival must never fall back to another Route.
    'presetSnapshot != nil else {',
]:
    if required not in watch_recorder_source:
        errors.append(f'Watch local recording preset guard is missing {required}')
# Signal Watch: routes are picked per recording from the iPhone-synced list,
# and the list is replaced by the recording screen while recording, so the
# Route cannot change mid-recording.
for required in [
    'private struct WatchRouteListScreen: View',
    'ForEach(bridge.snapshot.availablePresets)',
    'await localRecorder.start(using: bridge, route: route)',
    'if localRecorder.isRecording {\n            WatchRecordingScreen()',
]:
    if required not in watch_view_source:
        errors.append(f'Watch Route picker is missing {required}')
if 'guard !isRecording else { return }' not in watch_recorder_source:
    errors.append('Watch recorder must refuse to start (and re-route) while a recording is active')
for required in [
    'CaptureFilePicker(',
    'UIDocumentPickerViewController(',
    'contentTypes: [.data]',
    'reserveSharedItems(urls.count)',
    'matching: .screenshots',
    'CaptureRoutePickerView(viewModel: viewModel)',
    'capture_destination_banner',
    'ActivityFeedView(\n                        viewModel: viewModel,',
    'locationRequestTask?.cancel()',
    'voiceCaptureButton',
    'voiceCaptureDetailsBar',
    'Touch and hold to talk, then release to stop.',
    '.accessibilityAction(named: "Show detailed recording controls")',
    'capture_recording_options',
    'capture_recording_details',
    'capture_voice_recording',
    'Add to Draft',
    'Send Immediately',
    'capture_vox_selector',
    'Use Route destination defaults',
    'Attach audio to Capture',
    'capture_keyboard_listening',
    'capture_audio_import',
    'Watch Recordings',
]:
    if required not in quick_capture_ui_source:
        errors.append(f'Quick Capture hardening is missing {required}')

activity_feed_source = (root / 'Voxboard/Views/ActivityFeedView.swift').read_text()
if 'HistoryView(viewModel: viewModel, embedsInNavigationStack: false)' not in activity_feed_source:
    errors.append('Quick Capture history (Activity feed) must embed the unified HistoryView')

capture_route_picker_source = (root / 'Voxboard/Capture/CaptureRoutePickerView.swift').read_text()
for required in [
    'Set Up Destination',
    'CaptureDestinationEditorView(',
    'viewModel.saveSelectedPresetDestination(destination)',
]:
    if required not in capture_route_picker_source:
        errors.append(f'inline Capture destination setup is missing {required}')

quick_capture_view_model_source = (root / 'Voxboard App Shared/CaptureComposerViewModel.swift').read_text()
for required in [
    'saveSelectedPresetDestination',
    'CapturePresetStore.saveFlows',
    'refreshVoxProfiles()',
]:
    if required not in quick_capture_view_model_source:
        errors.append(f'Capture Preset destination persistence is missing {required}')

history_view_source = (root / 'Voxboard/Views/HistoryView.swift').read_text()
for required in ['LibraryItem.build(', 'viewModel.historyRecords', 'TextField("Search words, routes, files"', 'viewModel.clearHistory()']:
    if required not in history_view_source:
        errors.append(f'unified Capture and transcript history is missing {required}')

composer_source = (root / 'Voxboard/Capture/MarkdownComposerTextView.swift').read_text()
for required in ['accessibilityLabel = String(localized: "Capture note")', 'quick_capture_text', 'selectedRange']:
    if required not in composer_source:
        errors.append(f'selection-aware Markdown composer is missing {required}')

toolbar_source = '\n'.join(
    (root / path).read_text()
    for path in [
        'Voxboard/Capture/CaptureEditorToolbar.swift',
        'Voxboard App Shared/CaptureToolbarPreferences.swift',
    ]
)
for required in ['Set due date', 'Internal link', 'Insert current location', 'Change text case']:
    if required not in toolbar_source:
        errors.append(f'capture Markdown utility toolbar is missing {required}')

location_source = (
    root / 'Packages/VoxboardShared/Sources/VoxboardShared/CaptureLocationService.swift'
).read_text()
for required in ['requestLocation()', 'withTaskCancellationHandler', 'CaptureLocationError.timedOut']:
    if required not in location_source:
        errors.append(f'one-shot location service is missing {required}')
for forbidden in ['startUpdatingLocation()', 'startMonitoringSignificantLocationChanges()']:
    if forbidden in location_source:
        errors.append(f'one-shot location service must not call {forbidden}')

persistent_recorder_source = (root / 'Voxboard/PersistentRecorder.swift').read_text()
for required in [
    'case captureDraft(attachAudio: Bool)',
    'case runVox(flowID: String)',
    'captureDraftEventHandler?(.audio',
    'captureDraftEventHandler?(.transcript',
]:
    if required not in persistent_recorder_source:
        errors.append(f'Capture recording completion routing is missing {required}')
voice_session_source = (root / 'Voxboard/Capture/QuickCaptureVoiceSession.swift').read_text()
for required in [
    'CaptureVoiceLifecycle()',
    'beginInterruptionObservation',
    'expectedGeneration:',
    'transcriptionFinished(generation:',
    'persistCurrentRecording(generation:',
    'discardStagedRecording()',
    'purgeStaleTemporaryAudio()',
]:
    if required not in voice_session_source:
        errors.append(f'capture voice lifecycle hardening is missing {required}')

history_source = (
    root / 'Packages/VoxboardShared/Sources/VoxboardCaptureCore/CaptureHistoryStore.swift'
).read_text()
for required in [
    'public struct CaptureHistoryRecord',
    'relativeNotePath',
    'attachmentCount',
    'failureCategory',
]:
    if required not in history_source:
        errors.append(f'privacy-limited capture history is missing {required}')

secure_io = (root / 'Packages/VoxboardShared/Sources/VoxboardCaptureCore/SecureCaptureFileIO.swift').read_text()
if 'O_NOFOLLOW' not in secure_io or 'renameat(' not in secure_io:
    errors.append('descriptor-relative symlink-safe capture writes are missing')
voice_exporter = (
    root / 'Packages/VoxboardShared/Sources/VoxboardShared/TranscriptCaptureDestinationExporter.swift'
).read_text()
for required in [
    'let requestID = transcript.id',
    'try await inbox.enqueue(request)',
    'attachmentsFolderNameOverride',
    'audioPreparationFailed',
    'Never construct a reduced transcript-only retry',
]:
    if required not in voice_exporter:
        errors.append(f'durable idempotent voice delivery is missing {required}')

inbox_source = (
    root / 'Packages/VoxboardShared/Sources/VoxboardCaptureCore/CaptureInbox.swift'
).read_text()
for required in [
    'CaptureCompletionReceipt',
    'sanitizeLegacyCompletedRequests()',
    'privacy-safe tombstone',
]:
    if required not in inbox_source:
        errors.append(f'completed inbox privacy hardening is missing {required}')

if 'URLQueryItem(name: "source", value: "widget")' not in capture_widget:
    errors.append('Quick Capture widget does not retain widget provenance')
if 'URLQueryItem(name: "preset", value: voxID)' not in capture_widget:
    errors.append('Quick Capture widget does not retain its selected Capture Preset context')
quick_capture_model = (root / 'Voxboard App Shared/CaptureComposerViewModel.swift').read_text()
for required in [
    'initialLoadTask',
    'candidate.selectDestination(id)',
    'validateComposerLaunch',
    'applyComposerLaunch',
    'pendingPresetSwitch',
    'confirmPresetSwitch',
    'configureCaptureRouteOwnership',
    'appendRecordedTranscript',
    'stageRecordedAudio',
]:
    if required not in quick_capture_model:
        errors.append(f'Quick Capture cold-launch routing hardening is missing {required}')

intent_source = (root / 'Voxboard App Shared/CaptureAppIntents.swift').read_text()
shortcut_source = (root / 'Voxboard/VoxboardShortcutsProvider.swift').read_text()
if '@available(iOS 18.0, *)' in intent_source or '@available(iOS 18.0, *)' in shortcut_source:
    errors.append('capture App Intents must remain available on the supported iOS 17.6 deployment target')

shared_capture_model = root / 'Voxboard App Shared/CaptureComposerViewModel.swift'
if not shared_capture_model.exists():
    errors.append('the durable Capture composer model is not in the shared app source group')
if project.count('AA8000012FB00000AABB0001 /* Voxboard App Shared */') < 3:
    errors.append('the shared Capture app source group is not attached to both iOS and macOS targets')

mac_workspace = root / 'Voxboard Mac/MacCaptureWorkspaceView.swift'
mac_editor = root / 'Voxboard Mac/MacMarkdownComposerTextView.swift'
mac_root = (root / 'Voxboard Mac/MacRootView.swift').read_text()
mac_brand_path = root / 'Voxboard Mac/MacBrand.swift'
if not mac_workspace.exists() or 'MacCaptureWorkspaceView.swift in Sources' not in project:
    errors.append('capture-first macOS workspace is missing from the Mac target')
if not mac_editor.exists() or 'MacMarkdownComposerTextView.swift in Sources' not in project:
    errors.append('native macOS Markdown composer is missing from the Mac target')
if not mac_brand_path.exists() or 'MacBrand.swift in Sources' not in project:
    errors.append('Mac-only app-icon brand tokens are missing from the Mac target')
else:
    mac_brand_source = mac_brand_path.read_text()
    for required in [
        'enum MacBrand',
        'static let orange = Geist.accent',
        'static let onOrange = Geist.onAccent',
        'static let nativeSelectionOrange = Geist.accent',
        'static let orangeText = Geist.accentText',
        'static let attention = Geist.Palette.amber900',
        'static let appKitOrange = NSColor(',
        'srgbRed: 47.0 / 255.0',
        'struct MacAppIconView: View',
        'NSApplication.shared.applicationIconImage',
    ]:
        if required not in mac_brand_source:
            errors.append(f'Mac app-icon brand system is missing {required}')

mac_first_run_brand_source = (root / 'Voxboard Mac/MacFirstRunSetupView.swift').read_text()
# The Signal sidebar has no app-icon brand row. In Capture it starts directly
# with its ROUTES section, followed by ACTIVITY.
mac_sidebar_start = mac_root.find('struct MacSidebar: View {')
mac_sidebar_end = mac_root.find('\n}\n', mac_sidebar_start)
mac_sidebar_source = mac_root[mac_sidebar_start:mac_sidebar_end] if mac_sidebar_start >= 0 and mac_sidebar_end > mac_sidebar_start else ''
if not mac_sidebar_source:
    errors.append('Mac Signal sidebar (struct MacSidebar) could not be inspected')
else:
    capture_branch = re.search(
        r'if navigationState\.destination == \.capture \{\s*routesSection\s*activitySection\s*\}',
        mac_sidebar_source,
    )
    if capture_branch is None:
        errors.append('Mac Signal sidebar must show ROUTES then ACTIVITY in Capture')
    for required in ['sidebarHeader("ROUTES")', 'sidebarHeader("ACTIVITY")', 'private var routesSection: some View', 'private var activitySection: some View']:
        if required not in mac_sidebar_source:
            errors.append(f'Mac Signal sidebar is missing {required}')
    for forbidden in ['MacSidebarBrandView', 'MacAppIconView(']:
        if forbidden in mac_sidebar_source:
            errors.append(f'Mac Signal sidebar must not include an app-icon brand row: {forbidden}')
for source_name, source, required in [
    ('About settings', mac_root, 'MacAppIconView(size: 64)'),
    ('first-run setup', mac_first_run_brand_source, 'MacAppIconView(size: 76)'),
    ('Activity first-run state', (root / 'Voxboard Mac/MacActivityView.swift').read_text(), 'MacAppIconView(size: 52)'),
]:
    if required not in source:
        errors.append(f'Mac app-icon branding is missing from {source_name}')

mac_authored_hue_patterns = [
    re.compile(r'Color\.(red|green|blue|indigo|purple|pink|yellow|cyan|mint|teal|accentColor)\b'),
    re.compile(r'\.(foregroundStyle|foregroundColor|tint)\(\.(red|green|blue|indigo|purple|pink|yellow|cyan|mint|teal|orange)\)'),
    re.compile(r'symbolColor:\s*\.(red|green|blue|indigo|purple|pink|yellow|cyan|mint|teal|orange)\b'),
    re.compile(r'Geist\.(error|focus|success)\b'),
    re.compile(r'Geist\.Palette\.(red|blue|green|amber)[A-Za-z0-9]*\b'),
    re.compile(r'NSColor\.(system(Red|Green|Blue|Indigo|Purple|Pink|Yellow|Cyan|Mint|Teal|Orange)|controlAccentColor)\b'),
    re.compile(r'Color\(red:'),
]
for path in sorted((root / 'Voxboard Mac').glob('*.swift')):
    if path.name == 'MacBrand.swift':
        continue
    source = path.read_text()
    for pattern in mac_authored_hue_patterns:
        match = pattern.search(source)
        if match:
            line = source.count('\n', 0, match.start()) + 1
            errors.append(
                f'{path.name}:{line} bypasses the orange/black/white/grey Mac brand palette: '
                f'{match.group(0)}'
            )

brand_metadata = json.loads((root / 'app-store-input/brand.json').read_text())
if brand_metadata.get('accentColor') != '#FD9011':
    errors.append('app-store brand metadata must use the app-icon orange #FD9011')

app_icon_directory = root / 'Voxboard/Assets.xcassets/AppIcon.appiconset'
app_icon_manifest = json.loads((app_icon_directory / 'Contents.json').read_text())
mac_icon_filenames = {
    image.get('filename')
    for image in app_icon_manifest.get('images', [])
    if image.get('idiom') == 'mac' and image.get('filename')
}
if not mac_icon_filenames:
    errors.append('AppIcon catalog must retain macOS icon renditions')
for filename in mac_icon_filenames:
    if not (app_icon_directory / filename).is_file():
        errors.append(f'AppIcon catalog references missing Mac rendition {filename}')
if 'Assets.xcassets in Resources' not in project:
    errors.append('Mac target must retain the asset catalog that contains AppIcon')
mac_app_configurations = {
    name: settings
    for name, settings in build_configurations
    if settings.get('PRODUCT_BUNDLE_IDENTIFIER') == 'bontecou.Voxboard' and settings.get('SDKROOT') == 'macosx'
}
if sorted(mac_app_configurations) != ['Debug', 'Release'] or any(
    settings.get('ASSETCATALOG_COMPILER_APPICON_NAME') != 'AppIcon'
    for settings in mac_app_configurations.values()
):
    errors.append('Mac Debug and Release builds must retain AppIcon as their compiled app icon')

mac_accent_directory = root / 'Voxboard/Assets.xcassets/MacAccentColor.colorset'
mac_accent_manifest_path = mac_accent_directory / 'Contents.json'
if not mac_accent_manifest_path.is_file():
    errors.append('Mac-only native accent asset is missing')
else:
    mac_accent_manifest = json.loads(mac_accent_manifest_path.read_text())
    mac_accent_components = (
        mac_accent_manifest.get('colors', [{}])[0]
        .get('color', {})
        .get('components', {})
    )
    expected_mac_accent = {
        'red': '0.184',
        'green': '0.231',
        'blue': '0.910',
        'alpha': '1.000',
    }
    if mac_accent_components != expected_mac_accent:
        errors.append('Mac native selection accent must be Signal indigo #2F3BE8')
mac_accent_configurations = [
    settings for _, settings in build_configurations
    if settings.get('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME') == 'MacAccentColor'
]
if len(mac_accent_configurations) != 2 or any(
    settings.get('SDKROOT') != 'macosx' for settings in mac_accent_configurations
) or any(
    settings.get('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME') != 'MacAccentColor'
    for settings in mac_app_configurations.values()
):
    errors.append('only Mac Debug and Release builds must compile the MacAccentColor asset')

# The main window is intentionally small and task-oriented. Configuration is a
# native Settings concern, not another group of iOS-style sidebar destinations.
mac_destination_start = mac_root.find('enum MacDestination:')
mac_destination_end = mac_root.find('struct MacNavigationRequest:', mac_destination_start)
mac_destination_source = mac_root[mac_destination_start:mac_destination_end]
mac_destination_cases = re.findall(
    r'^\s*case\s+([A-Za-z][A-Za-z0-9_]*)\s*=\s*"([^"]+)"',
    mac_destination_source,
    flags=re.M,
)
expected_mac_destinations = [
    ('capture', 'Capture'),
    ('activity', 'Activity'),
    ('library', 'Library'),
]
if mac_destination_cases != expected_mac_destinations:
    errors.append(
        f'macOS main navigation is {mac_destination_cases}, '
        f'expected exactly {expected_mac_destinations}'
    )
for required in [
    'static let workDestinations: [MacDestination] = [.capture, .activity, .library]',
    'MacNavigationState',
    '@Observable',
    '@State private var navigationState: MacNavigationState',
    'openSettings: { openSettings() }',
    'openModels: { openSettingsPane(.transcription) }',
    'MacCaptureWorkspaceView(',
    'case .activity:',
    'MacActivityView(',
    'queue: recorder.recordingQueue',
    'retryOverride: { job, delivery in',
    'openCapture: { navigationState.select(.capture) }',
    'case .library:',
    'MacHistoryView(\n                viewModel: quickCaptureViewModel,',
    'MacActivityCounts.needsYou(queue: recorder.recordingQueue, viewModel: viewModel)',
    '.accessibilityLabel("Needs you")',
    'private func openSettingsPane(_ destination: MacSettingsDestination)',
]:
    if required not in mac_root:
        errors.append(f'macOS native main-window navigation is missing {required}')

mac_signal_components_source = (root / 'Voxboard Mac/MacSignalComponents.swift').read_text()
for required in [
    'let failedJobs = queue.actionableJobs.filter { $0.phase == .failed }',
    'failedJobs.count + viewModel.failedInboxCount',
]:
    if required not in mac_signal_components_source:
        errors.append(f'macOS Activity needs-you indicator is missing {required}')

mac_activity_path = root / 'Voxboard Mac/MacActivityView.swift'
if not mac_activity_path.exists() or 'MacActivityView.swift in Sources' not in project:
    errors.append('unified macOS Activity workspace is missing from the Mac target')
else:
    mac_activity_source = mac_activity_path.read_text()
    for required in [
        'struct MacActivityView: View',
        '@Environment(TranscriptStore.self)',
        'queue.actionableJobs',
        'let actionableJobIDs = Set(actionableJobs.map(\\.id))',
        '.filter { !actionableJobIDs.contains($0.id) }',
        'viewModel.historyRecords',
        'transcriptStore.transcripts',
        'private var signalPage: some View',
        '.sheet(isPresented: $showsDetail)',
        'activityDetail',
        'case inProgress',
        'case needsAttention',
        'await queue.refresh(recoverInterrupted: true)',
        'await queue.monitorDurableChanges()',
        'retryOverride:',
        'await queue.processNow(job)',
        'await queue.acknowledgeCopiedResult(job)',
        'NSWorkspace.shared.activateFileViewerSelecting([audioURL])',
        'await queue.discard(job)',
        'await viewModel.retryFailedInbox()',
        'Button("Start a Capture"',
    ]:
        if required not in mac_activity_source:
            errors.append(f'unified macOS Activity workspace is missing {required}')

mac_first_run_path = root / 'Voxboard Mac/MacFirstRunSetupView.swift'
if not mac_first_run_path.exists() or 'MacFirstRunSetupView.swift in Sources' not in project:
    errors.append('macOS first-run setup is missing from the Mac target')
else:
    mac_first_run_source = mac_first_run_path.read_text()
    for required in [
        'struct MacFirstRunSetupView: View',
        'await viewModel.load()',
        'NSOpenPanel()',
        'options: [.withSecurityScope]',
        'AVCaptureDevice.requestAccess(for: .audio)',
        'modelManager.selectedModel',
        'WhisperModelInfo.availableModels',
        'modelManager.startDownload(model)',
        'title: String(localized: "Quick Capture")',
        'MacHotKeyStore.load(for: .selectedPreset)',
        'openSettingsPane(.shortcuts)',
        'pathTemplate: "Journal/{period}.md"',
        'period: .daily',
        'try await viewModel.saveSelectedPresetDestination(destination)',
        'onComplete()',
        'onSkip()',
    ]:
        if required not in mac_first_run_source:
            errors.append(f'macOS first-run setup is missing {required}')
for required in [
    '@State private var showsFirstRunSetup: Bool',
    'CapturePresetStore.loadFlows()',
    '.sheet(isPresented: $showsFirstRunSetup)',
    'MacFirstRunSetupView(',
    'onComplete: completeFirstRunSetup',
    'onSkip: completeFirstRunSetup',
    'hasCompletedFirstRunSetup = true',
]:
    if required not in mac_root:
        errors.append(f'macOS root first-run presentation is missing {required}')

model_view_start = mac_root.find('private struct MacModelView: View')
model_view_end = mac_root.find('// MARK: - Capture Presets', model_view_start)
model_view_source = mac_root[model_view_start:model_view_end]
for required in [
    '.navigationTitle("Transcription Models")',
    'modelErrorBanner(error)',
    'Button("Dismiss")',
    'Button("Select")',
    'Button("Remove")',
    'Text("Use Existing…")',
    'Text("Download")',
]:
    if required not in model_view_source:
        errors.append(f'macOS Transcription settings surface is missing {required}')
if '.alert(' in model_view_source:
    errors.append('macOS model failures must remain inline instead of presenting an alert')
language_index = model_view_source.find('languageSection')
whisper_index = model_view_source.find('modelSection("02", "Whisper Models"')
if model_view_start < 0 or model_view_end < 0 or not (0 <= language_index < whisper_index):
    errors.append('macOS Models must keep Language visible before the model lists')
transcription_settings_start = mac_root.find('private var transcriptionSettings: some View')
transcription_settings_end = mac_root.find('private var transcriptionChoice:', transcription_settings_start)
if (
    mac_root.count('case .transcription:\n            transcriptionSettings') != 1
    or transcription_settings_start < 0
    or 'MacModelView()' not in mac_root[transcription_settings_start:transcription_settings_end]
):
    errors.append('macOS Transcription must have exactly one production Settings destination')
if 'case "04-models":\n            NavigationStack { MacModelView() }' not in mac_root:
    errors.append('macOS Models localization story must keep rendering the Settings model surface')
if mac_root.count('MacModelView()') != 2:
    errors.append('macOS Models must have only the Settings destination and DEBUG screenshot call sites')
if mac_root.count('case .presets:\n            MacCapturePresetSettingsView()') != 1:
    errors.append('macOS Capture Presets must have exactly one production Settings destination')
if 'case "05-presets":\n            NavigationStack { MacCapturePresetSettingsView() }' not in mac_root:
    errors.append('macOS Capture Presets localization story must keep rendering the Settings surface')
if mac_root.count('MacCapturePresetSettingsView()') != 2:
    errors.append('macOS Capture Presets must have only the Settings destination and DEBUG screenshot call sites')
if mac_root.count('case .templates:\n            MacEntryTemplateLibraryView()') != 1:
    errors.append('macOS Entry Templates must have exactly one production Settings destination')
preset_view_start = mac_root.find('private struct MacCapturePresetSettingsView: View')
preset_view_end = mac_root.find('private struct MacCapturePresetEditor: View', preset_view_start)
preset_view_source = mac_root[preset_view_start:preset_view_end]
for required in [
    'HStack(spacing: 0)',
    'List(selection: $selectedFlowId)',
    '.frame(width: 260)',
    'MacCapturePresetEditor(preset: $flows[index]',
    'Text("Select a Route")',
]:
    if required not in preset_view_source:
        errors.append(f'macOS Capture Presets Settings list/detail is missing {required}')
for removed in ['@Environment(\\.dismiss)', 'Button("Done")', '.sheet(', 'NavigationStack']:
    if removed in preset_view_source:
        errors.append(f'macOS Capture Presets Settings must remain embedded: {removed}')
settings_destination_start = mac_root.find('enum MacSettingsDestination')
settings_view_start = mac_root.find('struct MacSettingsView: View', settings_destination_start)
settings_view_end = mac_root.find('private enum MacPaywallPresentation', settings_view_start)
settings_destination_source = mac_root[settings_destination_start:settings_view_start]
settings_view_source = mac_root[settings_view_start:settings_view_end]
settings_cases = [
    'case general',
    'case recording',
    'case transcription',
    'case presets',
    'case templates',
    'case shortcuts',
    'case access',
    'case diagnostics',
    'case about',
]
settings_case_indexes = [settings_destination_source.find(case) for case in settings_cases]
# Every Settings destination must stay reachable from exactly one Signal tab.
settings_destination_cases = re.findall(r'^    case ([a-z]+)$', settings_destination_source, flags=re.M)
tab_panes_match = re.search(r'var panes: \[MacSettingsDestination\] \{(.*?)\n    \}', settings_destination_source, flags=re.S)
tab_pane_cases = [
    case
    for pane_list in re.findall(r'\[([^\]]*)\]', tab_panes_match.group(1) if tab_panes_match else '')
    for case in re.findall(r'\.([a-z]+)', pane_list)
]
if not settings_destination_cases or sorted(tab_pane_cases) != sorted(settings_destination_cases):
    errors.append('every macOS Settings destination must be reachable from exactly one Settings tab')
if any(index < 0 for index in settings_case_indexes) or settings_case_indexes != sorted(settings_case_indexes):
    errors.append(
        'macOS Settings category order must be General, Recording, Transcription, '
        'Presets, Templates, Shortcuts, Access, Diagnostics, About'
    )
for required in [
    'settingsTabBar',
    'ForEach(MacSettingsTab.allCases)',
    'settingsLinkRows(Array(MacSettingsTab.general.panes.dropFirst()))',
    'settingsLinkRows(Array(MacSettingsTab.vault.panes.dropFirst()))',
    'case .access:',
    'case .general:',
    'case .recording:',
    'MacRecordingSettingsView()',
    'case .transcription:',
    'MacModelView()',
    'case .presets:',
    'MacCapturePresetSettingsView()',
    'case .templates:',
    'MacEntryTemplateLibraryView()',
    'case .shortcuts:',
    'case .diagnostics:',
    'case .about:',
    'MacPaywallView(context: .settings, embeddedInSettings: true)',
    'MacHotKeyRecorderView(',
    'onCancel: { editingHotKeyTarget = nil }',
    'MacDebugLogView()',
    'mode.apply()',
    'await reloadHotKeyConfiguration()',
    'await storeManager.prepareForPurchases()',
]:
    if required not in settings_view_source:
        errors.append(f'dedicated macOS Settings hierarchy is missing {required}')
for removed in [
    'showCapturePresets',
    'showEntryTemplates',
    'showPaywall',
    'showDebug',
    '.sheet(',
    'MacHotKeyRecorderSheet',
]:
    if removed in settings_view_source:
        errors.append(f'macOS Settings must not retain duplicate or modal primary routing: {removed}')
paywall_view_start = mac_root.find('struct MacPaywallView: View', settings_view_end)
paywall_view_end = mac_root.find('private struct MacDebugLogView: View', paywall_view_start)
paywall_view_source = mac_root[paywall_view_start:paywall_view_end]
for required in [
    'embeddedInSettings: Bool',
    'presentation = embeddedInSettings ? .embeddedSettings : .modal',
    'if presentation == .modal',
    'await storeManager.restore()',
    'await storeManager.purchase(product, context: context)',
    'await storeManager.prepareForPurchases()',
]:
    if required not in paywall_view_source:
        errors.append(f'macOS embedded Access purchase surface is missing {required}')
hotkey_recorder_start = mac_root.find('private struct MacHotKeyRecorderView: View', settings_view_start)
hotkey_recorder_end = mac_root.find('private struct MacHotKeyCaptureView', hotkey_recorder_start)
hotkey_recorder_source = mac_root[hotkey_recorder_start:hotkey_recorder_end]
for required in ['let onCancel: () -> Void', 'onCancel()', 'onSave(capturedShortcut)', 'conflictingBindingName']:
    if required not in hotkey_recorder_source:
        errors.append(f'inline macOS shortcut recorder is missing {required}')
for removed in ['@Environment(\\.dismiss)', 'dismiss()', '.sheet(']:
    if removed in hotkey_recorder_source:
        errors.append(f'inline macOS shortcut recorder retains modal semantics: {removed}')
debug_view_start = mac_root.find('private struct MacDebugLogView: View', paywall_view_start)
debug_view_end = mac_root.find('private extension CapturePresetProcessingMode', debug_view_start)
debug_view_source = mac_root[debug_view_start:debug_view_end]
for required in ['Button("Clear")', 'Button("Refresh"', 'Button("Copy"', 'Reveal Data Folder', 'KeyboardDebugLog.shared.read()']:
    if required not in debug_view_source:
        errors.append(f'embedded macOS Diagnostics is missing {required}')
for removed in ['@Environment(\\.dismiss)', 'Button("Done")', '.frame(width: 760', '.sheet(']:
    if removed in debug_view_source:
        errors.append(f'embedded macOS Diagnostics retains modal semantics: {removed}')
if mac_app_source.count('Settings {') != 1:
    errors.append('macOS must retain exactly one native SwiftUI Settings scene')
settings_scene_start = mac_app_source.find('        Settings {')
settings_scene_end = mac_app_source.find('        MenuBarExtra(', settings_scene_start)
settings_scene_source = mac_app_source[settings_scene_start:settings_scene_end]
if 'MacSettingsView(recorder: recorder)' not in settings_scene_source or 'NavigationStack' in settings_scene_source:
    errors.append('the native macOS Settings scene must host MacSettingsView directly')
mac_template_source = (root / 'Voxboard Mac/MacEntryTemplateLibraryView.swift').read_text()
for required in [
    'List(selection: $selectedTemplateID)',
    'MacEntryTemplateEditor(',
    'drafts.append(template)',
    'selectedTemplateID = template.id',
    'CapturePresetStore.clearCaptureEntryTemplate(id)',
]:
    if required not in mac_template_source:
        errors.append(f'macOS Entry Templates Settings list/detail is missing {required}')
for removed in ['.sheet(', '@Environment(\\.dismiss)', 'templateToEdit', 'isAdding']:
    if removed in mac_template_source:
        errors.append(f'macOS Entry Templates Settings must edit inline instead of in sheets: {removed}')
history_view_start = mac_root.find('struct MacHistoryView: View')
history_view_end = mac_root.find('private enum MacUnifiedHistoryItem', history_view_start)
history_view_source = mac_root[history_view_start:history_view_end]
for required in [
    '@State private var selectedItemID: UUID?',
    'HSplitView {\n            libraryTablePane',
    'libraryPreviewPane',
    'ForEach(filteredItems)',
    'TextField("Search  ⌘F", text: $searchText)',
    'private var libraryPreviewPane: some View',
    'MacSignalSectionHeader("Transcript")',
    'MacCaptureDeliveryMetadataView(record: record) { reveal($0) }',
    'MacCaptureDeliveryMetadataView',
    'selectFallback(removing:',
    'reconcileSelection(requiringVisibleItem:',
    '.confirmationDialog(',
    'await viewModel.retryFailedInbox()',
    'await viewModel.clearHistory()',
]:
    if required not in history_view_source:
        errors.append(f'persistent macOS History list/detail is missing {required}')
for removed in ['selectedTranscript', '.sheet(', '@Environment(\\.dismiss)', 'Button("Done")']:
    if removed in history_view_source:
        errors.append(f'macOS History detail must remain embedded instead of modal: {removed}')
transcript_detail_start = mac_root.find('private struct MacTranscriptDetailView: View')
transcript_detail_end = mac_root.find('private struct MacCaptureHistoryDetailView: View', transcript_detail_start)
transcript_detail_source = mac_root[transcript_detail_start:transcript_detail_end]
for required in [
    'let delivery: CaptureHistoryRecord?',
    'Button("Copy Cleaned")',
    'Button("Copy Raw")',
    'transcriptSection(String(localized: "Raw Transcript")',
    'MacCaptureDeliveryMetadataView(record: delivery',
    'speakerDiarizationSkipReason',
    'ForEach(tags, id: \\.self)',
]:
    if required not in transcript_detail_source:
        errors.append(f'embedded macOS transcript detail is missing {required}')
for removed in ['@Environment(\\.dismiss)', 'Button("Done")', '.sheet(']:
    if removed in transcript_detail_source:
        errors.append(f'embedded macOS transcript detail retains modal semantics: {removed}')
history_item_start = mac_root.find('private enum MacUnifiedHistoryItem: Identifiable')
history_item_end = mac_root.find('private enum MacHistoryRevealError', history_item_start)
history_item_source = mac_root[history_item_start:history_item_end]
for required in [
    'var id: UUID',
    'case .transcript(let transcript, _): transcript.id',
    'case .capture(let record): record.requestID',
]:
    if required not in history_item_source:
        errors.append(f'macOS History selection identity is not stable: {required}')
if 'screenshotFixture: .localization' not in mac_root:
    errors.append('macOS History localization story must render populated list/detail evidence')
mac_workspace_source = mac_workspace.read_text() if mac_workspace.exists() else ''
for required in [
    'mac_quick_capture_submit',
    'mac_capture_destination_banner',
    'MacCaptureRouteInspector',
    'dropDestination(for: URL.self)',
    'CaptureComposerTextEditor().applying',
    'Add to Draft',
    'Send Immediately',
    'Transcribe Audio or Video',
    'Take Photo',
    'Import Scan or PDF',
    'Sketch',
    'Due date',
    'Internal link',
]:

    if required not in mac_workspace_source:
        errors.append(f'macOS Capture workspace is missing {required}')

def swift_brace_block(source: str, header: str) -> str | None:
    """Return `header` through its matching closing brace, or None."""
    start = source.find(header)
    if start < 0:
        return None
    open_index = source.find('{', start + len(header) - 1)
    if open_index < 0:
        return None
    depth = 0
    for index in range(open_index, len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    return None


# The Capture window has no toolbar (Signal: hidden title bar); every former
# toolbar command lives in the menu bar and acts on the focused Capture window.
mac_app_source = (root / 'Voxboard Mac/VoxboardMacApp.swift').read_text()
for required in [
    'requestNewCapture()',
    'showsClearDraftConfirmation',
    '@State private var selectedInspectorTool: MacCaptureInspectorTool? = .route',
    'recordToolbarButton',
    'sendToolbarButton',
    '.focusedSceneValue(\\.macCaptureMenuActions, menuActions)',
    'private var menuActions: MacCaptureMenuActions {',
]:
    if required not in mac_workspace_source:
        errors.append(f'native macOS Capture menu-bar commands are missing {required}')
for forbidden in [
    '.toolbar {',
    'ToolbarItem(',
    '@ToolbarContentBuilder',
    'captureToolbar',
    'presetToolbarMenu',
    'attachmentToolbarMenu',
    'formattingToolbarMenu',
    'recordingOptionsToolbarMenu',
    'moreToolbarMenu',
    'routeToolbarButton',
]:
    if forbidden in mac_workspace_source:
        errors.append(f'macOS Capture window must not keep the removed toolbar: {forbidden}')

if '.windowStyle(.hiddenTitleBar)' not in mac_app_source:
    errors.append('macOS main window must use .windowStyle(.hiddenTitleBar)')
if '.windowToolbarStyle(' in mac_app_source:
    errors.append('macOS main window must not configure the removed window toolbar style')
mac_commands_block = swift_brace_block(mac_app_source, '.commands {') or ''
if 'MacCaptureFormatCommands()' not in mac_commands_block:
    errors.append('macOS app commands must install MacCaptureFormatCommands()')
new_item_block = swift_brace_block(mac_commands_block, 'CommandGroup(replacing: .newItem) {') or ''
for required in [
    'Button("New Capture") {',
    'windowCoordinator.showMain(.newCapture)',
    '.keyboardShortcut("n", modifiers: .command)',
]:
    if required not in new_item_block:
        errors.append(f'macOS File › New Capture is missing {required}')

capture_command_menu = swift_brace_block(mac_commands_block, 'CommandMenu("Capture") {')
if capture_command_menu is None:
    errors.append('macOS menu bar is missing CommandMenu("Capture")')
elif capture_command_menu.count('MacCaptureMenuItems()') != 1:
    errors.append('MacCaptureMenuItems() must appear once inside CommandMenu("Capture")')
if mac_app_source.count('MacCaptureMenuItems()') != 1:
    errors.append('MacCaptureMenuItems() must be installed only in the Capture menu')

route_command_menu = swift_brace_block(mac_commands_block, 'CommandMenu("Route") {')
if route_command_menu is None:
    errors.append('macOS menu bar is missing CommandMenu("Route")')
else:
    for required in [
        'ForEach(Array(MacRouteCatalog.enabledRoutes(in: quickCaptureViewModel).enumerated()), id: \\.element.id) { index, route in',
        'MacRouteCatalog.select(route, in: quickCaptureViewModel)',
        '.disabled(!quickCaptureViewModel.canChangeCaptureRoute)',
        'if index < 4 {',
        'button.keyboardShortcut(KeyEquivalent(Character("\\(index + 1)")), modifiers: .command)',
        'Button("Quick Capture") {',
    ]:
        if required not in route_command_menu:
            errors.append(f'macOS Route menu (⌘1–⌘4) is missing {required}')
navigate_command_menu = swift_brace_block(mac_commands_block, 'CommandMenu("Navigate") {') or ''
for digit in '123':
    if f'.keyboardShortcut("{digit}", modifiers: [.command, .control])' not in navigate_command_menu:
        errors.append(f'macOS Navigate menu must move view {digit} to ⌃⌘{digit}')
for digit in '1234':
    if re.search(rf'keyboardShortcut\("{digit}", modifiers: \.command\)', mac_app_source):
        errors.append(f'⌘{digit} must stay reserved for the Route menu')

capture_menu_items = swift_brace_block(mac_workspace_source, 'struct MacCaptureMenuItems: View {')
if capture_menu_items is None:
    errors.append('macOS Capture menu items (MacCaptureMenuItems) are missing')
else:
    if '@FocusedValue(\\.macCaptureMenuActions) private var actions' not in capture_menu_items:
        errors.append('MacCaptureMenuItems must act on the focused Capture window')
    add_menu = swift_brace_block(capture_menu_items, 'Menu("Add") {') or ''
    for item in ['images', 'photo', 'scan', 'sketch', 'files', 'audio', 'webLink', 'paste']:
        if f'actions?.attach(.{item})' not in add_menu:
            errors.append(f'Capture › Add menu is missing attach(.{item})')
    after_recording = swift_brace_block(capture_menu_items, 'Menu("After Recording") {')
    if after_recording is None:
        errors.append('Capture menu is missing Menu("After Recording")')
    else:
        for required in [
            'Toggle("Add to Draft", isOn: radio(\\.sendsAfterRecording, on: false))',
            'Toggle("Send Immediately", isOn: radio(\\.sendsAfterRecording, on: true))',
        ]:
            if required not in after_recording:
                errors.append(f'Capture › After Recording is missing {required}')
    for required in [
        'Button("Transcribe Audio or Video…") { actions?.attach(.transcribe) }',
        'Toggle("Capture Details", isOn: Binding(',
        'set: { _ in actions?.toggleDetails() }',
        '.keyboardShortcut("i", modifiers: [.command, .option])',
        'Menu("Audio Source") {',
        'Toggle("Attach Audio to Draft"',
        'Button("Reveal Last Capture", action: reveal)',
        'Button(title, action: unlock)',
    ]:
        if required not in capture_menu_items:
            errors.append(f'MacCaptureMenuItems is missing {required}')

format_commands = swift_brace_block(mac_workspace_source, 'struct MacCaptureFormatCommands: Commands {')
if format_commands is None or 'CommandMenu("Format") {\n            MacCaptureFormatMenuItems()' not in format_commands:
    errors.append('MacCaptureFormatCommands must place MacCaptureFormatMenuItems under CommandMenu("Format")')
format_menu_items = swift_brace_block(mac_workspace_source, 'private struct MacCaptureFormatMenuItems: View {')
if format_menu_items is None:
    errors.append('macOS Format menu items (MacCaptureFormatMenuItems) are missing')
else:
    if '@FocusedValue(\\.macCaptureMenuActions) private var actions' not in format_menu_items:
        errors.append('MacCaptureFormatMenuItems must act on the focused Capture window')
    for required in [
        'Button("Internal link") { actions?.format(.internalLink) }\n                .keyboardShortcut("k", modifiers: .command)',
        'actions?.format(.bold)',
        'actions?.format(.italic)',
        'actions?.format(.heading(level))',
        'actions?.format(.markdownLink)',
        'actions?.format(.dueDate)',
        'actions?.format(.checklist)',
        'actions?.format(.bullet)',
        '.disabled(actions == nil)',
    ]:
        if required not in format_menu_items:
            errors.append(f'macOS Format menu is missing {required}')

capture_load_index = mac_workspace_source.find('await viewModel.load()')
capture_ready_index = mac_workspace_source.find(
    'windowCoordinator.captureWorkspaceReady(token: windowToken)'
)
if capture_load_index < 0 or capture_ready_index < 0 or capture_load_index >= capture_ready_index:
    errors.append('macOS Capture readiness must be announced only after the cold-load barrier')
if 'guard !Task.isCancelled else { return }' not in mac_workspace_source[
    capture_load_index:capture_ready_index
]:
    errors.append('a cancelled macOS Capture mount must not leave stale workspace readiness')
if '.onChange(of: viewModel.requestedInput)' in mac_workspace_source:
    errors.append('shared macOS requested input must not be consumed by every mounted Capture window')
if 'notification.object == nil' in mac_workspace_source:
    errors.append('macOS Capture notifications must reject nil broadcast payloads')
if mac_workspace_source.count(
    'guard let targetToken = notification.object as? String,'
) < 3:
    errors.append('macOS Capture notification handlers must require typed target-window tokens')
show_capture_handler = mac_workspace_source.find(
    '.onReceive(NotificationCenter.default.publisher(for: .macShowCapture))'
)
choose_files_handler = mac_workspace_source.find(
    '.onReceive(NotificationCenter.default.publisher(for: .macChooseCaptureFiles))'
)
if (
    show_capture_handler < 0
    or choose_files_handler < 0
    or 'consumeRequestedInput()' not in mac_workspace_source[
        show_capture_handler:choose_files_handler
    ]
):
    errors.append('only the token-targeted macOS Capture focus event may consume requested input')

route_inspector_start = mac_workspace_source.find('struct MacCaptureRouteInspector: View')
text_inspector_start = mac_workspace_source.find('private struct MacCaptureTextInspectorView: View')
workspace_surface_source = mac_workspace_source[:route_inspector_start]
route_inspector_source = mac_workspace_source[route_inspector_start:text_inspector_start]
for required in [
    'private enum MacCaptureInspectorTool',
    'case route',
    'case webLink',
    'case internalLink',
    'case camera',
    'case sketch',
    'case dueDate',
    '.inspector(isPresented: inspectorPresentationBinding)',
    'selectedInspectorTool: MacCaptureInspectorTool?',
    'selectInspectorTool(.route)',
    'selectInspectorTool(.webLink)',
    'selectInspectorTool(.internalLink)',
    'selectInspectorTool(.camera)',
    'selectInspectorTool(.sketch)',
    'selectInspectorTool(.dueDate)',
    'MacCaptureTextInspectorView(',
    'MacCameraCaptureView(',
    'MacSketchEditor(',
    'MacCaptureDueDateInspectorView(',
]:
    if required not in workspace_surface_source:
        errors.append(f'macOS Capture trailing inspector/tool routing is missing {required}')
for removed in [
    'showsRouteInspector',
    'showsLinkPrompt',
    'showsCamera',
    'showsSketch',
    'showsInternalLinkPrompt',
    'showsDueDate',
    'MacCaptureDueDateSheet',
]:
    if removed in workspace_surface_source:
        errors.append(f'macOS Capture accessory tools must not retain primary modal state: {removed}')
# The one consent alert protects a nonempty draft from external widget rerouting;
# accessory tools remain inline and may not introduce additional alerts.
preset_alert_start = workspace_surface_source.find('.alert(\n            "Switch Route?"')
preset_alert_end = workspace_surface_source.find('.onReceive(', preset_alert_start)
preset_alert_source = workspace_surface_source[preset_alert_start:preset_alert_end]
if workspace_surface_source.count('.alert(') != 1 or preset_alert_start < 0 or preset_alert_end < 0:
    errors.append('macOS Capture must have only the ID-bound preset-switch consent alert')
for required in [
    'presenting: viewModel.pendingPresetSwitch',
    'Task { await confirmPresetSwitch(id: pending.id) }',
    'viewModel.cancelPresetSwitch(id: pending.id)',
]:
    if required not in preset_alert_source:
        errors.append(f'macOS preset-switch consent is missing {required}')
if 'if await viewModel.confirmPresetSwitch(id: id)' not in workspace_surface_source:
    errors.append('macOS preset-switch consent must await the composer model confirmation')
if workspace_surface_source.count('.sheet(') != 1 or '.sheet(isPresented: $showsPaywall)' not in workspace_surface_source:
    errors.append('the StoreKit paywall must be the only app-authored sheet on the macOS Capture workspace')
for required in [
    'mac_capture_location_decision',
    'mac_capture_inbox_location_decision',
    'await viewModel.retryUnavailableLocation()',
    'sendWithoutUnavailableLocation(alwaysForPreset: false)',
    'sendWithoutUnavailableLocation(alwaysForPreset: true)',
    'await viewModel.cancelUnavailableLocation()',
    'await viewModel.sendInboxRequestWithoutLocation()',
    'sendInboxRequestWithoutLocation(alwaysForPreset: true)',
    'showsInboxDiscardConfirmation = true',
    '"Discard queued Capture?"',
    'await viewModel.discardInboxLocationRequest()',
]:
    if required not in workspace_surface_source:
        errors.append(f'inline macOS Capture location decisions are missing {required}')
for removed in ['.confirmationDialog(\n            "Location"', 'isPresented: Binding(\n                get: { viewModel.inboxLocationDecision != nil }']:
    if removed in workspace_surface_source:
        errors.append(f'macOS Capture location branching must be inline instead of a primary dialog: {removed}')
for required in [
    'NavigationStack',
    '.navigationDestination(isPresented: $isEditingDestination)',
    'embeddedInNavigation: true',
    'onClose: { isEditingDestination = false }',
    'viewModel.setEntryTemplateOverride($0)',
    'viewModel.useVoxRouteDefaults()',
    'chooseOneOffNote()',
    'viewModel.resolvedDestinationPreview',
]:
    if required not in route_inspector_source:
        errors.append(f'macOS Capture Route inspector hierarchy is missing {required}')
for removed in ['@Environment(\\.dismiss)', '.sheet(', 'Button("Done")', '.frame(minWidth: 620']:
    if removed in route_inspector_source:
        errors.append(f'macOS Capture Route inspector retains modal semantics: {removed}')
story_06_start = mac_root.find('case "06-recording-queue":')
story_07_start = mac_root.find('case "07-capture-route-inspector":', story_06_start)
story_08_start = mac_root.find('case "08-first-run-setup":', story_07_start)
story_default_start = mac_root.find('default:', story_08_start)
if min(story_06_start, story_07_start, story_08_start, story_default_start) < 0:
    errors.append('DEBUG macOS stories 06-08 must cover Activity, Capture Route, and First Run')
else:
    story_06_source = mac_root[story_06_start:story_07_start]
    story_07_source = mac_root[story_07_start:story_08_start]
    story_08_source = mac_root[story_08_start:story_default_start]
    for required in [
        'MacActivityView(',
        'queue: recorder.recordingQueue',
        'viewModel: quickCaptureViewModel',
        'openCapture: {}',
    ]:
        if required not in story_06_source:
            errors.append(f'DEBUG story 06 Activity fixture is missing {required}')
    if 'RecordingQueueView(' in story_06_source:
        errors.append('DEBUG story 06 must render unified Activity instead of the legacy queue view')
    for required in [
        'MacCaptureWorkspaceView(',
        'MacCaptureRouteInspector(viewModel: quickCaptureViewModel)',
    ]:
        if required not in story_07_source:
            errors.append(f'DEBUG story 07 Capture Route fixture is missing {required}')
    for required in [
        'MacFirstRunSetupView(',
        'viewModel: quickCaptureViewModel',
        'onComplete: {}',
        'onSkip: {}',
    ]:
        if required not in story_08_source:
            errors.append(f'DEBUG story 08 First Run fixture is missing {required}')

mac_screenshot_matrix_path = root / 'scripts/localization/screenshot_matrix.py'
if not mac_screenshot_matrix_path.exists():
    errors.append('localization screenshot matrix is missing')
else:
    mac_screenshot_matrix = mac_screenshot_matrix_path.read_text()
    mac_story_06_index = mac_screenshot_matrix.find('"06-recording-queue"')
    mac_story_07_index = mac_screenshot_matrix.find('"07-capture-route-inspector"')
    mac_story_08_index = mac_screenshot_matrix.find('"08-first-run-setup"')
    if not (
        0 <= mac_story_06_index < mac_story_07_index < mac_story_08_index
    ):
        errors.append(
            'macOS localization screenshot matrix must include Activity, Capture Route, '
            'and First Run as stories 06-08'
        )

mac_routes = root / 'Voxboard Mac/MacCaptureDestinationLibraryView.swift'
if not mac_routes.exists() or 'MacCaptureDestinationLibraryView.swift in Sources' not in project:
    errors.append('macOS capture-route management is missing from the Mac target')
for filename in [
    'MacCameraCaptureView.swift',
    'MacDocumentScanProcessor.swift',
    'MacSketchEditor.swift',
    'MacEntryTemplateLibraryView.swift',
]:
    path = root / 'Voxboard Mac' / filename
    if not path.exists() or f'{filename} in Sources' not in project:
        errors.append(f'macOS native Capture input/settings adapter is missing: {filename}')
mac_route_source = mac_routes.read_text() if mac_routes.exists() else ''
for required in [
    'let embeddedInNavigation: Bool',
    'embeddedInNavigation: Bool = false',
    'if embeddedInNavigation',
    '.frame(minWidth: 680, minHeight: 620)',
    'Button("Cancel", action: close)',
]:
    if required not in mac_route_source:
        errors.append(f'macOS destination editor must preserve modal sizing while supporting inspector navigation: {required}')
mac_camera_source = (root / 'Voxboard Mac/MacCameraCaptureView.swift').read_text()
mac_sketch_source = (root / 'Voxboard Mac/MacSketchEditor.swift').read_text()
for filename, source, required in [
    ('MacCameraCaptureView.swift', mac_camera_source, ['let onClose: () -> Void', 'camera.capture(completion: onCapture)', 'mac_capture_camera_shutter']),
    ('MacSketchEditor.swift', mac_sketch_source, ['let onClose: () -> Void', 'onSave(drawingData, png)', 'mac_capture_sketch_add']),
]:
    if '@Environment(\\.dismiss)' in source or 'dismiss()' in source:
        errors.append(f'{filename} must close explicitly from the Capture inspector instead of dismissing a sheet')
    for value in required:
        if value not in source:
            errors.append(f'{filename} inspector adapter is missing {value}')
due_date_start = mac_workspace_source.find('private struct MacCaptureDueDateInspectorView: View')
due_date_source = mac_workspace_source[due_date_start:]
for required in ['let onClose: () -> Void', 'let onInsert: (Date, Bool) -> Void', 'Toggle("Include time"', 'Button("Insert Due Date")']:
    if required not in due_date_source:
        errors.append(f'macOS due-date inspector is missing {required}')
if '@Environment(\\.dismiss)' in due_date_source or 'dismiss()' in due_date_source:
    errors.append('macOS due-date tool must close explicitly from the Capture inspector')
mac_app = (root / 'Voxboard Mac/VoxboardMacApp.swift').read_text()
if mac_app.count('.tint(MacBrand.orange)') < 3:
    errors.append('Mac main window, Settings, and screenshot roots must inherit the brand-orange tint')
if 'textView.insertionPointColor = MacBrand.appKitOrange' not in mac_editor.read_text():
    errors.append('Mac Markdown caret must use the app-icon orange instead of the system accent')
for required in [
    'quickCaptureViewModel',
    'await quickCaptureViewModel.processPendingInbox()',
    'case navigate(MacDestination)',
    'case newCapture',
    'showMain(.newCapture)',
    'showMain(.navigate(.activity))',
    'showMain(.navigate(.library))',
    'Settings {',
    '.windowStyle(.hiddenTitleBar)',
    'CommandMenu("Navigate")',
    'Button("Activity")',
    'Button("Library")',
    'CommandMenu("Capture")',
    'MacWindowCoordinator',
    'applicationDidBecomeActive',
    'applicationShouldTerminate',
    'flushDraftForTermination()',
]:
    if required not in mac_app:
        errors.append(f'macOS durable Capture integration is missing {required}')
if '@State private var navigationState' in mac_app:
    errors.append('MacNavigationState must remain owned by each MacRootView, not the app scene')
for required in [
    'deliverPendingCaptureRequestIfReady(to: token)',
    'case .navigate(.capture), .chooseFiles, .newCapture:',
    'NotificationCenter.default.post(name: .macShowCapture, object: token)',
    'NotificationCenter.default.post(name: .macClearCaptureDraft, object: token)',
]:
    if required not in mac_app:
        errors.append(f'macOS Capture routing is missing its readiness-gated delivery: {required}')
if mac_app.count(
    'NotificationCenter.default.post(name: .macShowCapture, object: token)'
) != 1:
    errors.append('macOS Capture focus must have one readiness-gated production sender')
if 'await quickCaptureViewModel.clearDraft()' in mac_app:
    errors.append('app commands must route destructive new-Capture requests through the ready Capture workspace')
handle_url_start = mac_app.find('private func handleURL(_ url: URL)')
handle_url_end = mac_app.find(
    '@MainActor\n    private static func consumePendingQuickCaptureOpenIfNeeded',
    handle_url_start,
)
handle_url_source = mac_app[handle_url_start:handle_url_end]
capture_case_start = handle_url_source.find('case "capture", "capture-request":')
capture_case_end = handle_url_source.find('} catch {', capture_case_start)
capture_success_source = handle_url_source[capture_case_start:capture_case_end]
deep_link_mutation_index = capture_success_source.find(
    'await quickCaptureViewModel.handleDeepLink(action)'
)
deep_link_route_index = capture_success_source.find(
    'windowCoordinator.showMain(.navigate(.capture))'
)
if (
    handle_url_start < 0
    or handle_url_end < 0
    or capture_case_start < 0
    or capture_case_end < 0
    or deep_link_mutation_index < 0
    or deep_link_route_index < deep_link_mutation_index
):
    errors.append('macOS deep links must finish mutation/persistence before targeted Capture delivery')
startup_start = mac_app.find('private static func consumePendingQuickCaptureOpenIfNeeded')
startup_end = mac_app.find('private func configureGlobalHotKeys()', startup_start)
startup_source = mac_app[startup_start:startup_end]
startup_value_index = startup_source.find('let incoming = CaptureDeepLinkDraft(')
startup_apply_index = startup_source.find(
    'await quickCaptureViewModel.handleDeepLink(.openComposer(incoming))'
)
startup_route_index = startup_source.find('windowCoordinator.showMain(.navigate(.capture))')
if not (
    startup_start >= 0
    and startup_end >= 0
    and 0 <= startup_value_index < startup_apply_index < startup_route_index
):
    errors.append('macOS startup handoff must validate/persist one complete launch before targeted Capture delivery')
for required in [
    'pendingQuickCaptureSourceKey',
    'pendingQuickCaptureVoxIdKey',
    'pendingQuickCaptureInputKey',
]:
    if required not in startup_source:
        errors.append(f'macOS atomic startup launch is missing {required}')
for partial_mutation in [
    'quickCaptureViewModel.requestCaptureSource(',
    'quickCaptureViewModel.requestVox(',
    'quickCaptureViewModel.requestedInput =',
]:
    if partial_mutation in startup_source:
        errors.append(f'macOS startup launch must not partially mutate source/preset/input: {partial_mutation}')
for removed_history_window in [
    'Window("Capture History", id: "history")',
    'historyWindow',
    'showHistory()',
]:
    if removed_history_window in mac_app:
        errors.append(
            f'macOS Library must route through the main navigation state, found {removed_history_window}'
        )
mac_recorder = (root / 'Voxboard Mac/MacRecorder.swift').read_text()
for required in [
    'OnDeviceTranscriptionService',
    'case captureDraft(attachAudio: Bool)',
    'case runPreset(flow: CapturePreset)',
    'liveTranscript(sessionID: UUID, finalizedText:',
    'source: .mac',
]:
    if required not in mac_recorder:
        errors.append(f'macOS unified recording flow is missing {required}')
for forbidden in ['WhisperContext(', 'ParakeetContext.load(']:
    if forbidden in mac_recorder:
        errors.append(f'macOS recorder must use the shared transcription service, not {forbidden}')
for required in ['lastRecoveryAudioURL', 'hasDurableAudioCopy', 'audioWasRequested']:
    if required not in mac_recorder:
        errors.append(f'macOS recorder is missing durable audio handoff guard {required}')
audio_recorder = (root / 'Packages/VoxboardShared/Sources/VoxboardShared/AudioRecorder.swift').read_text()
if 'recording.wav' in audio_recorder or 'recording_\\(UUID().uuidString.lowercased())' not in audio_recorder:
    errors.append('shared audio recorder must use a session-unique file URL')
mac_info = (root / 'Voxboard Mac/Info.plist').read_text()
for required in ['<string>voxboard</string>', 'NSSpeechRecognitionUsageDescription']:
    if required not in mac_info:
        errors.append(f'macOS Capture deep-link/live-preview configuration is missing {required}')

template_model = (root / 'Packages/VoxboardShared/Sources/VoxboardCaptureCore/CaptureModels.swift').read_text()
template_ui = (root / 'Voxboard/Views/CaptureDestinationLibraryView.swift').read_text()
if (
    'CaptureEntryTemplate' not in template_model
    or 'entryTemplateID' not in template_model
    or 'resolvedDestination' not in template_model
    or 'CaptureEntryTemplateLibraryView' not in template_ui
):
    errors.append('live reusable entry-template model/UI contract is missing')

website_root = root / 'website'
website_css = website_root / 'geist.css'
website_pages = [
    website_root / 'index.html',
    website_root / 'docs/index.html',
    website_root / 'privacy.html',
    website_root / 'terms.html',
    website_root / 'blog/index.html',
    website_root / 'blog/best-voice-to-text-keyboard-iphone/index.html',
]

website_docs = website_root / 'docs/index.html'
if website_docs.exists():
    docs_html = website_docs.read_text()
    for section_id in [
        'getting-started',
        'quick-capture',
        'presets',
        'models',
        'keyboard',
        'system-integrations',
        'apple-watch',
        'mac',
        'history-settings',
        'troubleshooting',
    ]:
        if f'id="{section_id}"' not in docs_html:
            errors.append(f'website documentation is missing the {section_id} category')
    for required in [
        'id="preset-location"',
        'Exact (default)',
        'two decimal places',
        'Apple’s system reverse geocoder',
        'Always Send Without Location',
        'never reacquire a later location',
        'completed Watch queue items',
        'independent Capture Bar action',
    ]:
        if required not in docs_html:
            errors.append(f'website location documentation is missing {required}')

website_llms = website_root / 'llms.txt'
if not website_llms.exists():
    errors.append('website is missing its root llms.txt agent interface')
else:
    llms = website_llms.read_text()
    for required in [
        '# Vox.md',
        'https://vox.isolated.tech/docs/',
        '## Keyboard Safety Note',
        'Allow Full Access',
        'Per-route location metadata is opt-in',
        'unattended Ask result is durable',
        'completed Watch queue items',
    ]:
        if required not in llms:
            errors.append(f'website llms.txt is missing {required}')

website_sitemap = website_root / 'sitemap.xml'
if not website_sitemap.exists():
    errors.append('website is missing sitemap.xml')
elif 'https://vox.isolated.tech/docs/' not in website_sitemap.read_text():
    errors.append('website sitemap does not include documentation')

for font_name in [
    'Geist-Regular.ttf',
    'Geist-Medium.ttf',
    'Geist-SemiBold.ttf',
    'GeistMono-Regular.ttf',
    'GeistMono-Medium.ttf',
    'LICENSE.txt',
    'BricolageGrotesque-Variable-latin.woff2',
    'InstrumentSerif-Italic-latin.woff2',
    'OFL-BricolageGrotesque-InstrumentSerif.txt',
]:
    if not (website_root / 'fonts' / font_name).exists():
        errors.append(f'website is missing bundled font asset {font_name}')

if not website_css.exists():
    errors.append('website is missing its shared stylesheet')
else:
    css = website_css.read_text()
    # The "raw file" theme: light paper only, Bricolage Grotesque over Geist Mono,
    # Signal blue plus a highlighter lime, Instrument Serif italic for spoken words.
    for required in [
        'color-scheme: light;',
        '--bg: #EFEEE8',
        '--ink: #121212',
        '--accent: #2F3BE8',
        '--lime: #E4FF3D',
        '--font-sans: "Bricolage Grotesque"',
        '--font-mono: "Geist Mono"',
        '--font-voice: "Instrument Serif"',
        'RAW FILE THEME',
        '@media (prefers-reduced-motion: reduce)',
        ':focus-visible',
    ]:
        if required not in css:
            errors.append(f'website stylesheet is missing {required}')
    for forbidden in ['JetBrains Mono', '#30D158', '--background-100: #ffffff', 'prefers-color-scheme: dark']:
        if forbidden in css:
            errors.append(f'website stylesheet still contains retired styling {forbidden}')
    for asset in re.findall(r'url\(["\']?([^"\')]+)', css):
        parsed = urlsplit(asset)
        if parsed.scheme or asset.startswith('data:'):
            continue
        if not (website_css.parent / parsed.path).resolve().exists():
            errors.append(f'website stylesheet references missing asset {asset}')

class WebsiteHTMLContractParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.main_count = 0
        self.h1_count = 0
        self.ids: list[str] = []
        self.references: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        attributes = dict(attrs)
        if tag == 'main':
            self.main_count += 1
        if tag == 'h1':
            self.h1_count += 1
        if attributes.get('id'):
            self.ids.append(attributes['id'])
        for name in ['href', 'src']:
            if attributes.get(name):
                self.references.append(attributes[name])
        if attributes.get('srcset'):
            self.references.extend(
                candidate.strip().split()[0]
                for candidate in attributes['srcset'].split(',')
            )

for page in website_pages:
    if not page.exists():
        errors.append(f'website page is missing: {page.relative_to(root)}')
        continue
    html = page.read_text()
    parser = WebsiteHTMLContractParser()
    parser.feed(html)
    if '<style>' in html:
        errors.append(f'{page.relative_to(root)} contains a legacy inline stylesheet')
    if 'geist.css' not in html:
        errors.append(f'{page.relative_to(root)} does not load the shared Geist stylesheet')
    if parser.main_count != 1:
        errors.append(f'{page.relative_to(root)} must contain exactly one main landmark')
    if parser.h1_count != 1:
        errors.append(f'{page.relative_to(root)} must contain exactly one h1')
    duplicate_ids = {value for value in parser.ids if parser.ids.count(value) > 1}
    if duplicate_ids:
        errors.append(f'{page.relative_to(root)} has duplicate IDs: {sorted(duplicate_ids)}')
    for reference in parser.references:
        parsed = urlsplit(reference)
        if parsed.scheme or parsed.netloc or reference.startswith(('#', 'mailto:', 'tel:', 'data:')):
            continue
        referenced_path = ((website_root / parsed.path.lstrip('/')) if parsed.path.startswith('/') else (page.parent / parsed.path)).resolve()
        if referenced_path.is_dir() or parsed.path.endswith('/'):
            referenced_path /= 'index.html'
        elif not referenced_path.exists() and not referenced_path.suffix:
            referenced_path = referenced_path.with_suffix('.html')
        if not referenced_path.is_relative_to(website_root.resolve()) or not referenced_path.exists():
            errors.append(
                f'{page.relative_to(root)} references missing local asset {reference}'
            )

if errors:
    print('Project contract failures:', file=sys.stderr)
    for error in errors:
        print(f'  - {error}', file=sys.stderr)
    raise SystemExit(1)

print('Project contracts passed.')
PY
