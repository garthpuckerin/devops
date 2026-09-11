#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const WORKFLOW_PATH = path.resolve(
  __dirname,
  "../.github/workflows/node-verification.yml",
);

const REQUIRED_SNIPPETS = [
  "workflow_call:",
  "permissions:\n  contents: read",
  "timeout-minutes: 30",
  "NODE_VERSION: ${{ inputs.node_version }}",
  "PNPM_VERSION: ${{ inputs.pnpm_version }}",
  "[[ \"$NODE_VERSION\" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+$ ]]",
  "[[ \"$PNPM_VERSION\" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+$ ]]",
  "pnpm install --frozen-lockfile",
  "if: inputs.contract_script != ''",
  "pnpm audit --audit-level=\"$AUDIT_LEVEL\"",
  "git diff --exit-code",
  "git diff --cached --exit-code",
  "git status --porcelain=v1 --untracked-files=all",
];

const REQUIRED_INPUTS = new Map([
  ["node_version", 'default: "24.16.0"'],
  ["pnpm_version", 'default: "9.14.2"'],
  ["lint_script", "default: lint"],
  ["unit_script", "default: test:coverage"],
  ["contract_script", 'default: ""'],
  ["build_script", "default: build"],
  ["audit_level", "default: high"],
  ["require_clean_build", "default: true"],
]);

const REQUIRED_STAGE_ORDER = [
  "Validate the reusable-workflow interface",
  "Checkout caller repository",
  "Set up Node.js",
  "Install the frozen toolchain",
  "Lint",
  "Unit coverage",
  "Repository contract tests",
  "Package vulnerability gate",
  "Production build",
  "Production build must leave the checkout clean",
];

function inputBlock(source, inputName) {
  const escaped = inputName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = source.match(
    new RegExp(`^      ${escaped}:\\r?\\n([\\s\\S]*?)(?=^      [A-Za-z0-9_]+:|^permissions:)`, "m"),
  );
  return match?.[1] ?? "";
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function verifyNodeVerificationWorkflowSource(source) {
  const failures = [];
  let checks = 0;

  for (const snippet of REQUIRED_SNIPPETS) {
    checks += 1;
    if (!source.includes(snippet)) {
      failures.push(`missing required contract fragment: ${snippet}`);
    }
  }

  for (const [inputName, expectedDefault] of REQUIRED_INPUTS) {
    checks += 1;
    const block = inputBlock(source, inputName);
    if (!block.includes("type:") || !block.includes(expectedDefault)) {
      failures.push(
        `input ${inputName} must remain typed with ${expectedDefault}`,
      );
    }
  }

  const uses = [...source.matchAll(/^\s*-?\s*uses:\s*([^@\s]+)@([^\s#]+)\s*$/gm)];
  checks += 1;
  if (uses.length !== 2) {
    failures.push(`expected exactly two external actions, found ${uses.length}`);
  }
  for (const [, action, revision] of uses) {
    checks += 1;
    if (!/^[0-9a-f]{40}$/.test(revision)) {
      failures.push(`${action} must be pinned by a full lowercase commit SHA`);
    }
  }

  let previous = -1;
  for (const stage of REQUIRED_STAGE_ORDER) {
    checks += 1;
    const matches = [
      ...source.matchAll(
        new RegExp(`^\\s*- name: ${escapeRegExp(stage)}\\r?$`, "gm"),
      ),
    ];
    const index = matches[0]?.index ?? -1;
    if (matches.length !== 1 || index <= previous) {
      failures.push(`stage must appear exactly once in contract order: ${stage}`);
    }
    previous = index;
  }

  checks += 1;
  if (/continue-on-error:\s*true|\|\|\s*true/.test(source)) {
    failures.push("required verification stages must fail closed");
  }

  checks += 1;
  if (!source.includes('run: pnpm run "$PACKAGE_SCRIPT"')) {
    failures.push("package scripts must be executed through the validated script-name boundary");
  }

  return { checks, failures };
}

function main() {
  const source = fs.readFileSync(WORKFLOW_PATH, "utf8");
  const result = verifyNodeVerificationWorkflowSource(source);
  if (result.failures.length > 0) {
    for (const failure of result.failures) {
      console.error(`node-verification contract: ${failure}`);
    }
    process.exitCode = 1;
    return;
  }
  console.log(`node-verification contract: ${result.checks}/${result.checks} checks passed`);
}

if (require.main === module) {
  main();
}

module.exports = { verifyNodeVerificationWorkflowSource };
