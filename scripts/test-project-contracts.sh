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

import ast
from pathlib import Path
import json
import plistlib
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

# --- StoreKit configuration ---------------------------------------------------
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

# --- Widget / share extension / main app build settings and entitlements ------
widget_bundle_id = 'bontecou.Voxboard.Voxboard-Widget'
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

# Release builds of the iOS app must keep the supported iOS 17.6 floor. Debug may
# raise its deployment target for debug-only tooling.
main_ios_configurations = {
    name: settings
    for name, settings in build_configurations
    if settings.get('PRODUCT_BUNDLE_IDENTIFIER') == 'bontecou.Voxboard'
    and settings.get('SDKROOT') != 'macosx'
}
if main_ios_configurations.get('Release', {}).get('IPHONEOS_DEPLOYMENT_TARGET') != '17.6':
    errors.append('main app Release deployment target contract is not iOS 17.6')

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
# --- Location purpose strings: Info.plist key + complete localization catalog --
location_purpose_contracts = [
    (root / 'Voxboard/Info.plist', root / 'Voxboard/InfoPlist.xcstrings', 'NSLocationWhenInUseUsageDescription'),
    (root / 'Voxboard Share Extension/Info.plist', root / 'Voxboard Share Extension/InfoPlist.xcstrings', 'NSLocationWhenInUseUsageDescription'),
    (root / 'Voxboard Watch/Info.plist', root / 'Voxboard Watch/InfoPlist.xcstrings', 'NSLocationWhenInUseUsageDescription'),
    (root / 'Voxboard Mac/Info.plist', root / 'Voxboard Mac/InfoPlist.xcstrings', 'NSLocationUsageDescription'),
]
expected_location_locales = {
    'ar', 'bn', 'de', 'en', 'es', 'fr', 'hi', 'id', 'it', 'ja', 'ko', 'nl',
    'pl', 'pt-BR', 'ru', 'ta', 'th', 'tr', 'uk', 'ur', 'vi', 'zh-Hans', 'zh-Hant',
}
for plist_path, catalog_path, key in location_purpose_contracts:
    english_value = plistlib.loads(plist_path.read_bytes()).get(key)
    if not isinstance(english_value, str) or not english_value.strip():
        errors.append(f'{plist_path.relative_to(root)} is missing {key}')
        continue
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

# --- macOS app configuration --------------------------------------------------
mac_info = (root / 'Voxboard Mac/Info.plist').read_text()
for required in ['<string>voxboard</string>', 'NSSpeechRecognitionUsageDescription']:
    if required not in mac_info:
        errors.append(f'macOS Capture deep-link/live-preview configuration is missing {required}')

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

mac_accent_manifest_path = root / 'Voxboard/Assets.xcassets/MacAccentColor.colorset/Contents.json'
if not mac_accent_manifest_path.is_file():
    errors.append('Mac-only native accent asset is missing')
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

# CI runs the shared VoxboardTests scheme.
if not (root / 'Voxboard.xcodeproj/xcshareddata/xcschemes/VoxboardTests.xcscheme').exists():
    errors.append('VoxboardTests must have a shared Xcode scheme')

if errors:
    print('Project contract failures:', file=sys.stderr)
    for error in errors:
        print(f'  - {error}', file=sys.stderr)
    raise SystemExit(1)

print('Project contracts passed.')
PY
