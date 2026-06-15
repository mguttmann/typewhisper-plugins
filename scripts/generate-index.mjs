import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { resolve, join } from "node:path";
import { execSync } from "node:child_process";
import { createHash } from "node:crypto";

const rootDir = resolve(dirname(new URL(import.meta.url).pathname), "..");
const pluginsDir = join(rootDir, "plugins");
const indexPath = join(rootDir, "plugin-index.json");

function dirname(path) {
  return path.substring(0, path.lastIndexOf("/"));
}

const repoUrl = "https://github.com/mguttmann/typewhisper-plugins";

const plugins = [];

if (!existsSync(pluginsDir)) {
  console.log("No plugins directory found.");
  writeFileSync(
    indexPath,
    JSON.stringify(
      { schemaVersion: 1, generatedAt: new Date().toISOString(), plugins: [] },
      null,
      2,
    ) + "\n",
  );
  process.exit(0);
}

const dirs = readdirSync(pluginsDir).filter((d) => {
  const manifestPath = join(pluginsDir, d, "manifest.json");
  return existsSync(manifestPath);
});

for (const dir of dirs) {
  const manifestPath = join(pluginsDir, dir, "manifest.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf-8"));

  // Check for icon.png
  const iconPath = join(pluginsDir, dir, "icon.png");
  const hasIconFile = existsSync(iconPath);
  const iconUrl = hasIconFile
    ? `${repoUrl}/raw/main/plugins/${dir}/icon.png`
    : null;

  // Try to find release info from git tags
  let publishedAt = new Date().toISOString();
  try {
    const tag = `${manifest.slug}-v${manifest.version}`;
    const tagDate = execSync(`git log -1 --format=%aI "${tag}" 2>/dev/null`, {
      encoding: "utf-8",
      cwd: rootDir,
    }).trim();
    if (tagDate) publishedAt = tagDate;
  } catch {
    // No tag found, use current time
  }

  // Build download info from releases
  const downloads = {};
  for (const platform of manifest.platforms) {
    const filename = `${manifest.slug}-${manifest.version}-${platform}.bundle.zip`;
    const releasePath = join(rootDir, "dist", filename);

    if (existsSync(releasePath)) {
      const fileBuffer = readFileSync(releasePath);
      const sha256 = createHash("sha256").update(fileBuffer).digest("hex");
      const size = statSync(releasePath).size;
      downloads[platform] = {
        url: `${repoUrl}/releases/download/${manifest.slug}-v${manifest.version}/${filename}`,
        sha256,
        size,
      };
    } else {
      // Generate expected URL even without local file
      downloads[platform] = {
        url: `${repoUrl}/releases/download/${manifest.slug}-v${manifest.version}/${filename}`,
        sha256: "",
        size: 0,
      };
    }
  }

  plugins.push({
    id: manifest.id,
    slug: manifest.slug,
    name: manifest.name,
    author: manifest.author,
    authorUrl: manifest.authorUrl || null,
    version: manifest.version,
    description: manifest.description,
    categories: manifest.categories,
    platforms: manifest.platforms,
    minAppVersion: manifest.minAppVersion,
    license: manifest.license,
    homepage: manifest.homepage || null,
    sourceUrl: `${repoUrl}/tree/main/plugins/${dir}`,
    icon: manifest.icon || null,
    iconUrl,
    apiDocsUrl: manifest.apiDocsUrl || null,
    readmeUrl: `${repoUrl}/raw/main/plugins/${dir}/README.md`,
    downloads,
    publishedAt,
    principalClass: manifest.principalClass,
  });
}

plugins.sort((a, b) => a.name.localeCompare(b.name));

const index = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  plugins,
};

writeFileSync(indexPath, JSON.stringify(index, null, 2) + "\n");
console.log(
  `Generated plugin-index.json with ${plugins.length} plugin(s).`,
);
