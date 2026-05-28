#!/usr/bin/env python3
"""Generate the TypeWhisper *runtime* plugin manifest from the catalog manifest.

The catalog (typewhisper-plugins) manifest schema and the schema TypeWhisper's
runtime actually loads from an installed .bundle are different:

  catalog schema : id, slug, name, author, version, description, categories[],
                   platforms[], minAppVersion, license, principalClass, icon
  runtime schema : id, name, version, author, description, minHostVersion,
                   sdkCompatibilityVersion, minOSVersion, category,
                   iconSystemName, principalClass

TypeWhisper 1.5.0+ rejects a bundle whose manifest lacks `sdkCompatibilityVersion`
with: "Missing SDK compatibility metadata for this TypeWhisper runtime."

So the bundle that gets installed must carry the *runtime* manifest, not the
catalog one. This script derives the runtime manifest from the catalog manifest
(single source of truth for id/name/version/author/description) and adds the
runtime-specific fields.

Usage: make-runtime-manifest.py <catalog-manifest.json> <output-runtime-manifest.json>
"""
import json
import sys

if len(sys.argv) != 3:
    sys.exit("usage: make-runtime-manifest.py <catalog-manifest.json> <output.json>")

src = json.load(open(sys.argv[1]))
categories = src.get("categories") or []

runtime = {
    "id": src["id"],
    "name": src["name"],
    "version": src["version"],
    "author": src["author"],
    "description": src["description"],
    "minHostVersion": "1.4.0",
    "sdkCompatibilityVersion": "v1",
    "minOSVersion": "14.0",
    "category": categories[0] if categories else "llm",
    "iconSystemName": "brain.head.profile",
    "principalClass": src["principalClass"],
}

with open(sys.argv[2], "w") as f:
    json.dump(runtime, f, indent=2)
    f.write("\n")

print(f"Wrote runtime manifest -> {sys.argv[2]}")
