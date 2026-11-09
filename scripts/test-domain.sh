#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/Sources/BudsDomain" "$test_root/Tests/BudsDomainTests" \
    "$test_root/Sources/BudsStorage" "$test_root/Tests/BudsStorageTests" \
    "$test_root/Sources/BudsWidgetData" "$test_root/Tests/BudsWidgetDataTests"
cp "$repo_root"/Sources/BudsDomain/*.swift "$test_root/Sources/BudsDomain/"
cp "$repo_root"/Tests/BudsDomainTests/*.swift "$test_root/Tests/BudsDomainTests/"
cp "$repo_root"/Sources/BudsStorage/*.swift "$test_root/Sources/BudsStorage/"
cp "$repo_root"/Tests/BudsStorageTests/*.swift "$test_root/Tests/BudsStorageTests/"
cp "$repo_root"/Sources/BudsWidgetData/*.swift "$test_root/Sources/BudsWidgetData/"
cp "$repo_root"/Tests/BudsWidgetDataTests/*.swift "$test_root/Tests/BudsWidgetDataTests/"

cat > "$test_root/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WasiiBudsDomainTests",
    targets: [
        .target(name: "BudsDomain"),
        .target(name: "BudsStorage", dependencies: ["BudsDomain"]),
        .target(name: "BudsWidgetData"),
        .testTarget(name: "BudsDomainTests", dependencies: ["BudsDomain"]),
        .testTarget(name: "BudsStorageTests", dependencies: ["BudsStorage", "BudsDomain"]),
        .testTarget(name: "BudsWidgetDataTests", dependencies: ["BudsWidgetData"]),
    ]
)
SWIFT

swift test --package-path "$test_root"
