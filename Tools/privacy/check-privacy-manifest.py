#!/usr/bin/env python3
"""개인정보 명세(PrivacyInfo.xcprivacy)의 키와 값을 Xcode 의 정의와 대조한다.

    python3 Tools/privacy/check-privacy-manifest.py [경로]

허용 목록은 Xcode 26.6 의
`DVTCorePlistStructDefs.dvtplugin/.../DVTCorePlistStructDefs.xcplugindata`
(확장점 com.apple.xcode.plist.structure-definition.app-privacy.privacy) 에서
옮겨 적었다. 애플 서버의 검사기(ITMS-91056)는 이 정의보다 느슨하지 않다.

왜 있나: 사유 배열의 키를 `NSPrivacyAccessedAPIReasons` 라고 적어 두 빌드가
ITMS-91056 으로 돌아왔다. 맞는 이름은 `NSPrivacyAccessedAPITypeReasons` 다.
plutil 은 키 이름을 모르니 통과시키고, altool --validate-app 도 안 본다.
올린 뒤 메일로만 알 수 있는 종류라, 올리기 전에 여기서 잡는다.
"""

import plistlib
import sys
from pathlib import Path

DEFAULT = Path("App/PrivacyInfo.xcprivacy")

TOP_KEYS = {
    "NSPrivacyTracking": bool,
    "NSPrivacyTrackingDomains": list,
    "NSPrivacyAccessedAPITypes": list,
    "NSPrivacyCollectedDataTypes": list,
}

# 카테고리 → 허용 사유. Xcode 정의의 localizedString 접두사로 묶었다.
API_REASONS = {
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"3EC4.1", "54BD.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"7D9E.1", "85F4.1", "B728.1", "E174.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"0A2A.1", "3B52.1", "C617.1", "DDA9.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1", "3D61.1", "8FFB.1"},
    "NSPrivacyAccessedAPICategoryUserDefaults": {"1C8F.1", "AC6B.1", "C56D.1", "CA92.1"},
}
API_ENTRY_KEYS = {"NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"}

COLLECTED_ENTRY_KEYS = {
    "NSPrivacyCollectedDataType",
    "NSPrivacyCollectedDataTypeLinked",
    "NSPrivacyCollectedDataTypeTracking",
    "NSPrivacyCollectedDataTypePurposes",
}
COLLECTED_TYPES = {
    "NSPrivacyCollectedDataType" + name for name in (
        "AdvertisingData", "AudioData", "BrowsingHistory", "CoarseLocation", "Contacts",
        "CrashData", "CreditInfo", "CustomerSupport", "DeviceID", "EmailAddress",
        "EmailsOrTextMessages", "EnvironmentScanning", "Fitness", "GameplayContent",
        "Hands", "Head", "Health", "Name", "OtherDataTypes", "OtherDiagnosticData",
        "OtherFinancialInfo", "OtherUsageData", "OtherUserContactInfo", "OtherUserContent",
        "PaymentInfo", "PerformanceData", "PhoneNumber", "PhotosorVideos", "PhysicalAddress",
        "PreciseLocation", "ProductInteraction", "PurchaseHistory", "SearchHistory",
        "SensitiveInfo", "UserID",
    )
}
COLLECTED_PURPOSES = {
    "NSPrivacyCollectedDataTypePurpose" + name for name in (
        "Analytics", "AppFunctionality", "DeveloperAdvertising", "Other",
        "ProductPersonalization", "ThirdPartyAdvertising",
    )
}


def check(path: Path) -> list[str]:
    problems: list[str] = []
    try:
        with open(path, "rb") as f:
            manifest = plistlib.load(f)
    except Exception as error:  # noqa: BLE001 — 무엇이든 읽기 실패는 곧 결함
        return [f"plist 로 읽을 수 없습니다: {error}"]
    if not isinstance(manifest, dict):
        return ["최상위가 dict 가 아닙니다"]

    for key, value in manifest.items():
        if key not in TOP_KEYS:
            problems.append(f"모르는 최상위 키: {key}")
        elif not isinstance(value, TOP_KEYS[key]):
            problems.append(f"{key} 는 {TOP_KEYS[key].__name__} 이어야 합니다")

    if manifest.get("NSPrivacyTracking") and not manifest.get("NSPrivacyTrackingDomains"):
        problems.append("NSPrivacyTracking 이 true 면 NSPrivacyTrackingDomains 가 있어야 합니다")
    for domain in manifest.get("NSPrivacyTrackingDomains", []):
        if not isinstance(domain, str):
            problems.append(f"NSPrivacyTrackingDomains 항목이 문자열이 아닙니다: {domain!r}")

    for index, entry in enumerate(manifest.get("NSPrivacyAccessedAPITypes", [])):
        where = f"NSPrivacyAccessedAPITypes[{index}]"
        if not isinstance(entry, dict):
            problems.append(f"{where} 가 dict 가 아닙니다")
            continue
        for key in set(entry) - API_ENTRY_KEYS:
            problems.append(f"{where}: 모르는 키 {key} (맞는 이름: {sorted(API_ENTRY_KEYS)})")
        for key in API_ENTRY_KEYS - set(entry):
            problems.append(f"{where}: 필수 키 {key} 가 없습니다")
        category = entry.get("NSPrivacyAccessedAPIType")
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons")
        if category not in API_REASONS:
            problems.append(f"{where}: 모르는 카테고리 {category!r}")
        elif isinstance(reasons, list):
            if not reasons:
                problems.append(f"{where}: 사유가 비어 있습니다")
            for reason in reasons:
                if reason not in API_REASONS[category]:
                    problems.append(
                        f"{where}: {category} 에 허용되지 않는 사유 {reason!r} "
                        f"(허용: {sorted(API_REASONS[category])})")
        elif reasons is not None:
            problems.append(f"{where}: NSPrivacyAccessedAPITypeReasons 는 배열이어야 합니다")

    for index, entry in enumerate(manifest.get("NSPrivacyCollectedDataTypes", [])):
        where = f"NSPrivacyCollectedDataTypes[{index}]"
        if not isinstance(entry, dict):
            problems.append(f"{where} 가 dict 가 아닙니다")
            continue
        for key in set(entry) - COLLECTED_ENTRY_KEYS:
            problems.append(f"{where}: 모르는 키 {key}")
        for key in COLLECTED_ENTRY_KEYS - set(entry):
            problems.append(f"{where}: 필수 키 {key} 가 없습니다")
        if entry.get("NSPrivacyCollectedDataType") not in COLLECTED_TYPES:
            problems.append(f"{where}: 모르는 데이터 종류 {entry.get('NSPrivacyCollectedDataType')!r}")
        for key in ("NSPrivacyCollectedDataTypeLinked", "NSPrivacyCollectedDataTypeTracking"):
            if key in entry and not isinstance(entry[key], bool):
                problems.append(f"{where}: {key} 는 불리언이어야 합니다")
        purposes = entry.get("NSPrivacyCollectedDataTypePurposes", [])
        if not purposes:
            problems.append(f"{where}: 목적이 비어 있습니다")
        for purpose in purposes:
            if purpose not in COLLECTED_PURPOSES:
                problems.append(f"{where}: 모르는 목적 {purpose!r}")

    return problems


def main() -> None:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    problems = check(path)
    if problems:
        print(f"❌ {path}")
        for problem in problems:
            print(f"   · {problem}")
        sys.exit(1)
    print(f"✅ {path} — 키와 값이 Xcode 정의와 맞습니다")


if __name__ == "__main__":
    main()
