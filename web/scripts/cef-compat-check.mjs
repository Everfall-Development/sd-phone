import { access, readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const webDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const buildDirectory = path.join(webDirectory, 'build');
const errors = [];

async function exists(filePath) {
    try {
        await access(filePath);
        return true;
    } catch {
        return false;
    }
}

async function read(filePath, label) {
    if (!(await exists(filePath))) {
        errors.push(`${label} is missing: ${path.relative(webDirectory, filePath)}`);
        return '';
    }
    return readFile(filePath, 'utf8');
}

async function collectAssets(directory, suffixes) {
    const entries = await readdir(directory, { withFileTypes: true });
    const files = [];
    for (const entry of entries) {
        const filePath = path.join(directory, entry.name);
        if (entry.isDirectory()) {
            files.push(...await collectAssets(filePath, suffixes));
            continue;
        }
        if (suffixes.some(suffix => entry.name.endsWith(suffix))) files.push(filePath);
    }
    return files;
}

function requirePattern(contents, pattern, label) {
    if (!pattern.test(contents)) errors.push(label);
}

function rejectPatterns(contents, patterns, label) {
    for (const [name, pattern] of patterns) {
        if (pattern.test(contents)) errors.push(`${label} uses ${name}, which is not in Chromium 103`);
    }
}

const post103JavaScript = [
    ['Array.prototype.toReversed/toSorted/toSpliced', /\.(?:toReversed|toSorted|toSpliced)\s*\(/],
    ['Array.prototype.with', /\.with\s*\(/],
    ['Promise.withResolvers', /\bPromise\.withResolvers\s*\(/],
    ['Temporal', /\bTemporal(?:\.|\b)/],
    ['Iterator helpers', /\bIterator\.prototype\.(?:map|filter|take|drop|flatMap|reduce|toArray)\b/],
    ['RegExp.escape', /\bRegExp\.escape\s*\(/],
];

const post103Css = [
    [':has()', /:has\s*\(/i],
    ['color-mix()', /color-mix\s*\(/i],
    ['@starting-style', /@starting-style/i],
    ['field-sizing', /field-sizing\s*:/i],
    ['text-wrap: balance', /text-wrap\s*:\s*balance/i],
    ['dynamic viewport units', /(?:^|[^a-z0-9.-])(?:\d*\.)?\d+(?:dvh|dvw|svh|svw|lvh|lvw)\b/i],
    ['anchor positioning', /(?:anchor-name|position-anchor|anchor\s*\()/i],
    ['view transitions', /view-transition-name|::view-transition/i],
];

const viteConfig = await read(path.join(webDirectory, 'vite.config.ts'), 'Vite config');
requirePattern(viteConfig, /target\s*:\s*['"]chrome103['"]/, 'Vite JS target must be chrome103');
requirePattern(viteConfig, /cssTarget\s*:\s*['"]chrome103['"]/, 'Vite CSS target must be chrome103');

const indexHtml = await read(path.join(webDirectory, 'index.html'), 'Source entry');
requirePattern(
    indexHtml,
    /<style[^>]*>[\s\S]*?(?:html|body|#root)[\s\S]*?background\s*:\s*transparent\s*!important[\s\S]*?<\/style>/i,
    'Source entry must contain an inline transparent pre-CSS guard',
);
requirePattern(
    indexHtml,
    /<style[^>]*>[\s\S]*?html\s*\{[^}]*color-scheme\s*:\s*normal\s*!important[\s\S]*?<\/style>/i,
    'Source entry must normalize color-scheme before bundled CSS loads',
);

const builtEntryPath = path.join(buildDirectory, 'index.html');
const builtEntry = await read(builtEntryPath, 'Built entry');
if (builtEntry) {
    requirePattern(builtEntry, /<style[^>]*>[\s\S]*?background\s*:\s*transparent\s*!important[\s\S]*?<\/style>/i, 'Built entry must retain the transparent pre-CSS guard');
    requirePattern(builtEntry, /<style[^>]*>[\s\S]*?color-scheme\s*:\s*normal\s*!important[\s\S]*?<\/style>/i, 'Built entry must retain the normal color-scheme guard');

    const assetReferences = [...builtEntry.matchAll(/(?:src|href)=["']([^"']+)["']/g)].map(match => match[1]);
    for (const assetReference of assetReferences) {
        if (/^(?:https?:|data:|#)/.test(assetReference)) continue;
        const assetPath = path.resolve(buildDirectory, assetReference);
        if (!(await exists(assetPath))) errors.push(`Built entry references a missing asset: ${assetReference}`);
    }
}

if (await exists(buildDirectory)) {
    const assets = await collectAssets(buildDirectory, ['.js', '.css']);
    for (const asset of assets) {
        const contents = await readFile(asset, 'utf8');
        const relativeAsset = path.relative(webDirectory, asset);
        if (asset.endsWith('.js')) rejectPatterns(contents, post103JavaScript, relativeAsset);
        if (asset.endsWith('.css')) rejectPatterns(contents, post103Css, relativeAsset);
    }
}

if (errors.length) {
    for (const error of errors) console.error(`CEF compatibility error: ${error}`);
    process.exitCode = 1;
} else {
    console.log('CEF compatibility check passed for Chromium 103 (source, built entry, JS, and CSS).');
}
