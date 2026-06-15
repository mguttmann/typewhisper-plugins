import { readFileSync } from "node:fs";
import { resolve, dirname, basename } from "node:path";

const manifestPath = process.argv[2];
if (!manifestPath) {
  console.error("Usage: node validate-manifest.mjs <path-to-manifest.json>");
  process.exit(1);
}

const schemaPath = resolve(
  dirname(new URL(import.meta.url).pathname),
  "../manifest-schema.json",
);

const schema = JSON.parse(readFileSync(schemaPath, "utf-8"));
const manifest = JSON.parse(readFileSync(manifestPath, "utf-8"));

let errors = [];

// Check required fields
for (const field of schema.required) {
  if (manifest[field] === undefined || manifest[field] === null) {
    errors.push(`Missing required field: ${field}`);
  }
}

// Check field types and patterns
for (const [key, value] of Object.entries(manifest)) {
  const prop = schema.properties[key];
  if (!prop) {
    errors.push(`Unknown field: ${key}`);
    continue;
  }

  if (prop.type === "string" && typeof value !== "string") {
    errors.push(`${key} must be a string`);
    continue;
  }

  if (prop.type === "array" && !Array.isArray(value)) {
    errors.push(`${key} must be an array`);
    continue;
  }

  if (prop.type === "string" && typeof value === "string") {
    if (prop.pattern && !new RegExp(prop.pattern).test(value)) {
      errors.push(`${key} does not match pattern ${prop.pattern}: "${value}"`);
    }
    if (prop.minLength && value.length < prop.minLength) {
      errors.push(`${key} must be at least ${prop.minLength} characters`);
    }
    if (prop.maxLength && value.length > prop.maxLength) {
      errors.push(`${key} must be at most ${prop.maxLength} characters`);
    }
  }

  if (prop.type === "array" && Array.isArray(value)) {
    if (prop.minItems && value.length < prop.minItems) {
      errors.push(`${key} must have at least ${prop.minItems} items`);
    }
    if (prop.items?.enum) {
      for (const item of value) {
        if (!prop.items.enum.includes(item)) {
          errors.push(
            `${key} contains invalid value "${item}". Valid: ${prop.items.enum.join(", ")}`,
          );
        }
      }
    }
    if (prop.uniqueItems && new Set(value).size !== value.length) {
      errors.push(`${key} must contain unique items`);
    }
  }
}

// Check slug matches directory name
const pluginDir = dirname(manifestPath);
const dirName = basename(pluginDir);
if (manifest.slug && manifest.slug !== dirName) {
  errors.push(
    `slug "${manifest.slug}" does not match directory name "${dirName}"`,
  );
}

if (errors.length > 0) {
  console.error("Manifest validation failed:");
  for (const err of errors) {
    console.error(`  - ${err}`);
  }
  process.exit(1);
} else {
  console.log(`Manifest valid: ${manifest.name} v${manifest.version}`);
}
