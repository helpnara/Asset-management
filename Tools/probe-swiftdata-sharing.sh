#!/bin/bash
# SwiftData 가 CKShare 공유를 지원하나 — SDK 에 직접 물어본다.
#
# 4차(가족 공유) 착수 전에 답이 있어야 하는 질문이다. 인터넷 자료가 엇갈려서
# (지원 안 함 vs `cloudKitDatabase: .shared` 가 있음) **컴파일러를 심판으로 쓴다.**
# 원격 세션에는 Xcode 가 없으므로 CI 의 macOS 러너에서 돈다.
#
# 이 스크립트는 **아무것도 실패시키지 않는다.** 조사 결과를 찍기만 한다.

set -uo pipefail

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK: $SDK"
echo "Swift: $(xcrun swift --version 2>&1 | head -1)"
echo

# ── 1. SwiftData 의 공개 API 를 통째로 꺼내 본다 ──────────────────────────
# 시스템 프레임워크는 .swiftinterface 를 SDK 안에 두고 있다. 이게 있으면
# "무엇이 있고 무엇이 없나" 를 추측이 아니라 목록으로 볼 수 있다.
echo "══ 1. SwiftData 공개 API 에서 공유 관련 낱말 찾기 ══"
IFACE=$(find "$SDK/System/Library/Frameworks/SwiftData.framework" \
          -name "*.swiftinterface" 2>/dev/null | head -5)
if [ -z "$IFACE" ]; then
  echo "  .swiftinterface 를 못 찾았습니다. 아래 타입검사 결과로 판단하세요."
else
  for f in $IFACE; do
    echo "  파일: $f"
    echo "  ── CKShare · share · Shared 가 나오는 줄 ──"
    grep -n -i "ckshare\|sharedCloudDatabase\|func share\|\.shared\b" "$f" | head -30 \
      || echo "    (없음)"
    echo "  ── cloudKitDatabase 관련 ──"
    grep -n "cloudKitDatabase\|CloudKitDatabase" "$f" | head -20 || echo "    (없음)"
  done
fi
echo

# ── 2. 후보 API 를 하나씩 타입검사한다 ────────────────────────────────────
# 컴파일되면 있는 것이고, 안 되면 없는 것이다. 한 개가 실패해도 나머지는 계속한다.
echo "══ 2. 후보 API 타입검사 (컴파일되면 존재) ══"
WORK=$(mktemp -d)

probe() {
  local name="$1"; local code="$2"
  printf '%s\n' "$code" > "$WORK/probe.swift"
  if xcrun swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios17.0 \
       "$WORK/probe.swift" 2> "$WORK/err.txt"; then
    echo "  ✅ $name"
  else
    echo "  ❌ $name"
    sed 's/^/       /' "$WORK/err.txt" | grep -m 3 "error:" || true
  fi
}

probe "ModelConfiguration(cloudKitDatabase: .private(...))" '
import SwiftData
@Model final class T { var a: Int = 0 }
func f() throws {
  _ = ModelConfiguration(cloudKitDatabase: .private("iCloud.com.helpnara.slowrich"))
}'

probe "cloudKitDatabase: .automatic / .none" '
import SwiftData
func f() {
  _ = ModelConfiguration(cloudKitDatabase: .automatic)
  _ = ModelConfiguration(cloudKitDatabase: .none)
}'

# ★ 핵심 질문. 공유 데이터베이스를 SwiftData 가 직접 열 수 있나?
probe "★ cloudKitDatabase: .shared (공유 DB 를 SwiftData 가 여나)" '
import SwiftData
func f() {
  _ = ModelConfiguration(cloudKitDatabase: .shared)
}'

# ★ 두 번째 핵심. 레코드를 공유로 내보내는 API 가 SwiftData 에 있나?
probe "★ ModelContainer 에 share(...) 류 메서드" '
import CloudKit
import SwiftData
@Model final class T { var a: Int = 0 }
func f(container: ModelContainer, model: T) async throws {
  _ = try await container.share([model], to: nil)
}'

probe "★ ModelContext 에 share(...) 류 메서드" '
import CloudKit
import SwiftData
@Model final class T { var a: Int = 0 }
func f(context: ModelContext, model: T) async throws {
  _ = try await context.share([model], to: nil)
}'

# ── 3. 물러설 곳이 있나 — Core Data 쪽은 확실히 되는지 ────────────────────
echo
echo "══ 3. 물러설 곳 — NSPersistentCloudKitContainer 의 공유 API ══"
probe "NSPersistentCloudKitContainer.share(_:to:)" '
import CoreData
import CloudKit
func f(c: NSPersistentCloudKitContainer, o: NSManagedObject) async throws {
  _ = try await c.share([o], to: nil)
}'

probe "NSPersistentCloudKitContainerOptions(databaseScope:)" '
import CoreData
import CloudKit
func f() {
  let o = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.x")
  o.databaseScope = .shared
}'

# ── 4. raw CloudKit 은 언제나 된다 (참고 구현이 쓰는 길) ──────────────────
echo
echo "══ 4. raw CloudKit (참고 구현이 실제로 쓰는 길) ══"
probe "CKShare · sharedCloudDatabase · CKModifyRecordsOperation" '
import CloudKit
func f() {
  let c = CKContainer(identifier: "iCloud.com.helpnara.slowrich")
  _ = c.sharedCloudDatabase
  let zone = CKRecordZone(zoneName: "z")
  let share = CKShare(recordZoneID: zone.zoneID)
  share[CKShare.SystemFieldKey.title] = "가족 자산" as CKRecordValue
  let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
  op.isAtomic = true
}'

rm -rf "$WORK"
echo
echo "══ 끝 ══"
