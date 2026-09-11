const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  verifyNodeVerificationWorkflowSource,
} = require("./verify-node-verification-workflow.cjs");

const SOURCE = fs.readFileSync(
  path.resolve(__dirname, "../.github/workflows/node-verification.yml"),
  "utf8",
);

function replaceRequired(source, from, to) {
  assert.ok(source.includes(from), `fixture must contain ${from}`);
  return source.replace(from, to);
}

test("accepts the canonical reusable workflow", () => {
  const result = verifyNodeVerificationWorkflowSource(SOURCE);
  assert.deepEqual(result.failures, []);
  assert.ok(result.checks >= 30);
});

const mutations = [
  ["missing workflow_call", "workflow_call:", "workflow_dispatch:"],
  ["elevated permissions", "contents: read", "contents: write"],
  ["mutable action", "actions/checkout@11d5960a326750d5838078e36cf38b85af677262", "actions/checkout@v4"],
  ["floating Node version", 'default: "24.16.0"', 'default: "24"'],
  ["floating pnpm version", 'default: "9.14.2"', 'default: "9"'],
  ["unfrozen install", "pnpm install --frozen-lockfile", "pnpm install"],
  ["missing contract guard", "if: inputs.contract_script != ''", "if: always()"],
  ["weakened audit", 'pnpm audit --audit-level="$AUDIT_LEVEL"', "pnpm audit || true"],
  ["missing tracked clean check", "git diff --exit-code", "git status --short"],
  ["missing index clean check", "git diff --cached --exit-code", "git status --short"],
  ["missing untracked clean check", "git status --porcelain=v1 --untracked-files=all", "git status --ignored"],
  ["success-by-skip", "timeout-minutes: 30", "timeout-minutes: 30\n    continue-on-error: true"],
  [
    "out-of-order security and build stages",
    "- name: Package vulnerability gate",
    "- name: ZZZ Package vulnerability gate",
  ],
  [
    "removed interface validation",
    '[[ "$NODE_VERSION" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+$ ]]',
    'echo "$NODE_VERSION"',
  ],
];

for (const [name, from, to] of mutations) {
  test(`rejects ${name}`, () => {
    const mutated = replaceRequired(SOURCE, from, to);
    const result = verifyNodeVerificationWorkflowSource(mutated);
    assert.notDeepEqual(result.failures, []);
  });
}
