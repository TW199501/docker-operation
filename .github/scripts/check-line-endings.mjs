#!/usr/bin/env node
// =============================================================================
// check-line-endings.mjs — 強制執行 .gitattributes 的換行符規範
//
// 規則(來自 .gitattributes):
//   - 預設所有 text 檔案行尾必須是 LF
//   - Windows 專屬批次檔 (.bat / .cmd / .ps1) 必須是 CRLF
//
// CI fail 條件:
//   - text 檔含 \r\n(CRLF)
//   - Windows 批次檔含純 \n 但無 \r\n(LF only,應該要 CRLF)
//
// 用法:node .github/scripts/check-line-endings.mjs
// =============================================================================

import { readFileSync, readdirSync } from 'node:fs';
import { join, extname } from 'node:path';

const ROOT = process.cwd();

// 應該強制 LF 的副檔名(對應 .gitattributes 第 9-26 行)
const LF_EXTS = new Set([
  '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs',
  '.vue', '.json', '.yml', '.yaml', '.md',
  '.html', '.htm', '.css', '.scss',
  '.cs', '.csproj', '.sln', '.dart', '.sql', '.sh',
  // docker-operation 客製:Docker / Shell / 設定檔
  '.bash', '.conf', '.ini', '.env',
]);

// 應該強制 CRLF 的副檔名(Windows 專屬)
const CRLF_EXTS = new Set(['.bat', '.cmd', '.ps1']);

// 連同無副檔名但團隊認定為 text 的檔案
const LF_FILENAMES = new Set([
  'LICENSE', 'README', 'CHANGELOG', 'CODEOWNERS',
  '.gitignore', '.gitattributes', '.editorconfig',
  '.npmrc', '.dockerignore',
  // docker-operation 客製
  'Dockerfile', '.shellcheckrc', '.hadolint.yaml',
]);

const IGNORE_DIRS = new Set([
  'node_modules', '.git', 'dist', 'build', 'coverage',
  '.cache', '.turbo', '.nuxt', '.output',
  'playwright-report', 'test-results', 'allure-results', 'allure-report',
]);

/** @type {{ file: string, want: 'LF' | 'CRLF', has: 'CRLF' | 'LF-only' }[]} */
const violations = [];

function classifyFile(filename) {
  const ext = extname(filename).toLowerCase();
  if (LF_EXTS.has(ext)) return 'LF';
  if (CRLF_EXTS.has(ext)) return 'CRLF';
  if (LF_FILENAMES.has(filename)) return 'LF';
  return null;
}

function checkFile(filepath, want) {
  let buf;
  try {
    buf = readFileSync(filepath);
  } catch {
    return;
  }
  const text = buf.toString('utf8');
  const hasCRLF = /\r\n/.test(text);
  const hasLF = /(?<!\r)\n/.test(text);

  if (want === 'LF' && hasCRLF) {
    violations.push({ file: filepath, want: 'LF', has: 'CRLF' });
  } else if (want === 'CRLF' && hasLF && !hasCRLF) {
    violations.push({ file: filepath, want: 'CRLF', has: 'LF-only' });
  }
}

function walk(dir) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    if (IGNORE_DIRS.has(entry.name)) continue;
    const fp = join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fp);
    } else {
      const want = classifyFile(entry.name);
      if (want) checkFile(fp, want);
    }
  }
}

walk(ROOT);

if (violations.length === 0) {
  console.log('✅ 換行符檢查通過(全 repo 符合 .gitattributes 規範)');
  process.exit(0);
}

console.log(`❌ 換行符違規 ${violations.length} 個檔案:\n`);
for (const v of violations) {
  console.log(`  [${v.want} 應該,實際 ${v.has}] ${v.file.replace(ROOT, '.').replace(/\\/g, '/')}`);
}
console.log('\n修復方式:');
console.log('  1. Windows: 用 VS Code 開檔,右下角點換行符切換 LF/CRLF 後存檔');
console.log('  2. 批次: git add --renormalize . && git commit -m "chore: normalize line endings"');
console.log('  3. 規範來源: .gitattributes');
process.exit(1);
