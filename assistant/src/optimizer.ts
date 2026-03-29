#!/usr/bin/env node
/**
 * Skill Optimizer — Karpathy-style autoresearch for SKILL.md files.
 *
 * Takes a skill + eval config, runs test prompts through Claude,
 * scores outputs against criteria, and iteratively refines the
 * SKILL.md until success rate hits the target.
 *
 * Usage: npx tsx src/optimizer.ts <skill-dir> [--iterations N] [--samples N] [--target 0.9]
 */

import Anthropic from "@anthropic-ai/sdk";
import {
  readFileSync,
  writeFileSync,
  existsSync,
  mkdirSync,
  appendFileSync,
  copyFileSync,
} from "node:fs";
import { join, basename } from "node:path";

// ─── Types ────────────────────────────────────────────────────────────

interface TestCase {
  prompt: string;
  criteria: string[];
}

interface EvalConfig {
  description: string;
  targetRate: number;
  maxIterations: number;
  samplesPerIteration: number;
  criteria: string[];
  testCases: TestCase[];
  model?: string;
}

interface EvalResult {
  testCase: TestCase;
  output: string;
  scores: { criterion: string; pass: boolean; reason: string }[];
  passRate: number;
  allPassed: boolean;
}

interface IterationLog {
  iteration: number;
  timestamp: number;
  results: EvalResult[];
  overallRate: number;
  improved: boolean;
  action: "keep" | "discard" | "baseline";
  changes: string;
}

// ─── Eval Engine ──────────────────────────────────────────────────────

class SkillOptimizer {
  private client: Anthropic;
  private model: string;
  private skillDir: string;
  private skillFile: string;
  private evalConfig: EvalConfig;
  private logFile: string;
  private historyFile: string;
  private bestRate = 0;
  private bestSkill = "";
  private iterations: IterationLog[] = [];

  constructor(skillDir: string, overrides?: Partial<EvalConfig>) {
    this.skillDir = skillDir;
    this.skillFile = join(skillDir, "SKILL.md");
    this.logFile = join(skillDir, "optimizer.log");
    this.historyFile = join(skillDir, "optimizer-history.jsonl");

    if (!existsSync(this.skillFile)) {
      throw new Error(`No SKILL.md found in ${skillDir}`);
    }

    const evalFile = join(skillDir, "eval.json");
    if (!existsSync(evalFile)) {
      throw new Error(
        `No eval.json found in ${skillDir}. Create one with test cases and criteria.`,
      );
    }

    this.evalConfig = {
      ...JSON.parse(readFileSync(evalFile, "utf-8")),
      ...overrides,
    };

    this.model = this.evalConfig.model || "claude-sonnet-4-6";
    this.client = new Anthropic();
    this.bestSkill = readFileSync(this.skillFile, "utf-8");
  }

  private log(msg: string): void {
    const line = `[${new Date().toISOString()}] ${msg}`;
    console.log(line);
    appendFileSync(this.logFile, line + "\n");
  }

  private async callClaude(
    system: string,
    userMessage: string,
    maxTokens = 4096,
  ): Promise<string> {
    const resp = await this.client.messages.create({
      model: this.model,
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content: userMessage }],
    });
    return resp.content
      .filter((b): b is Anthropic.TextBlock => b.type === "text")
      .map((b) => b.text)
      .join("");
  }

  /** Run a single test case against the skill and score it */
  private async evalTestCase(
    skill: string,
    tc: TestCase,
  ): Promise<EvalResult> {
    const criteria = [...this.evalConfig.criteria, ...tc.criteria];

    // Step 1: Run the test prompt with the skill as system context
    const systemPrompt = `You are an AI assistant with the following skill loaded:\n\n${skill}\n\nFollow the skill instructions precisely.`;
    const output = await this.callClaude(systemPrompt, tc.prompt, 2048);

    // Step 2: Score the output using a judge prompt
    const judgeSystem = `You are an eval judge. Score an AI output against specific criteria.
For each criterion, determine if it PASSES or FAILS with a brief reason.
Output valid JSON only — no markdown fences, no extra text.`;

    const judgePrompt = `## Test Prompt
${tc.prompt}

## AI Output
${output}

## Criteria to Judge
${criteria.map((c, i) => `${i + 1}. ${c}`).join("\n")}

Score each criterion. Output JSON:
{
  "scores": [
    { "criterion": "...", "pass": true/false, "reason": "brief reason" }
  ]
}`;

    let scores: EvalResult["scores"] = [];
    try {
      const judgeResp = await this.callClaude(judgeSystem, judgePrompt, 2048);
      const cleaned = judgeResp.replace(/```json\s*|```\s*/g, "").trim();
      const parsed = JSON.parse(cleaned);
      scores = parsed.scores || [];
    } catch {
      scores = criteria.map((c) => ({
        criterion: c,
        pass: false,
        reason: "Judge failed to parse",
      }));
    }

    const passed = scores.filter((s) => s.pass).length;
    const passRate = scores.length > 0 ? passed / scores.length : 0;

    return {
      testCase: tc,
      output: output.slice(0, 500),
      scores,
      passRate,
      allPassed: passRate === 1,
    };
  }

  /** Run all test cases (or a random sample) and return aggregate score */
  private async runEvalRound(skill: string): Promise<{
    results: EvalResult[];
    overallRate: number;
  }> {
    const cases = this.evalConfig.testCases;
    const sampleSize = Math.min(
      this.evalConfig.samplesPerIteration,
      cases.length,
    );

    // Sample test cases
    const shuffled = [...cases].sort(() => Math.random() - 0.5);
    const sample = shuffled.slice(0, sampleSize);

    const results: EvalResult[] = [];
    for (const tc of sample) {
      try {
        const result = await this.evalTestCase(skill, tc);
        results.push(result);
        const icon = result.allPassed ? "  ✓" : "  ✗";
        this.log(
          `${icon} "${tc.prompt.slice(0, 60)}..." → ${(result.passRate * 100).toFixed(0)}%`,
        );
      } catch (err: unknown) {
        this.log(
          `  ! Error on "${tc.prompt.slice(0, 40)}...": ${(err as Error).message}`,
        );
        results.push({
          testCase: tc,
          output: "",
          scores: [],
          passRate: 0,
          allPassed: false,
        });
      }
    }

    const overallRate =
      results.length > 0
        ? results.filter((r) => r.allPassed).length / results.length
        : 0;

    return { results, overallRate };
  }

  /** Ask Claude to refine the skill based on failure analysis */
  private async refineSkill(
    currentSkill: string,
    failedResults: EvalResult[],
    currentRate: number,
    iteration: number,
  ): Promise<string> {
    const failureSummary = failedResults
      .map((r) => {
        const failed = r.scores.filter((s) => !s.pass);
        return `Prompt: "${r.testCase.prompt.slice(0, 100)}"
Failed criteria:
${failed.map((f) => `  - ${f.criterion}: ${f.reason}`).join("\n")}
Output excerpt: "${r.output.slice(0, 200)}"`;
      })
      .join("\n\n---\n\n");

    const system = `You are an expert prompt engineer optimizing a SKILL.md file.
Your goal is to refine the skill instructions so the AI follows them more reliably.
Output ONLY the complete updated SKILL.md content — nothing else. No explanations, no fences.`;

    const prompt = `## Current SKILL.md
${currentSkill}

## Eval Criteria
${this.evalConfig.criteria.map((c) => `- ${c}`).join("\n")}

## Current Success Rate
${(currentRate * 100).toFixed(0)}% (target: ${(this.evalConfig.targetRate * 100).toFixed(0)}%)

## Iteration
${iteration} of ${this.evalConfig.maxIterations}

## Failure Analysis (${failedResults.length} failed test cases)
${failureSummary}

## Instructions
Revise the SKILL.md to fix these failures. Strategies:
- Add explicit instructions for the patterns that are failing
- Add examples of correct output format if format is the issue
- Add constraints or guardrails for common drift patterns
- Restructure for clarity if instructions are ambiguous
- Remove contradictory or confusing guidance

Keep the skill focused and concise. Do not bloat it with unnecessary content.
Output the complete revised SKILL.md content:`;

    return this.callClaude(system, prompt, 8192);
  }

  /** Main optimization loop */
  async optimize(): Promise<void> {
    const skillName = basename(this.skillDir);
    this.log(`\n${"═".repeat(60)}`);
    this.log(`Optimizing skill: ${skillName}`);
    this.log(
      `Target: ${(this.evalConfig.targetRate * 100).toFixed(0)}% | Max iterations: ${this.evalConfig.maxIterations} | Samples/iter: ${this.evalConfig.samplesPerIteration}`,
    );
    this.log(`Test cases: ${this.evalConfig.testCases.length} | Criteria: ${this.evalConfig.criteria.length}`);
    this.log(`${"═".repeat(60)}\n`);

    // Backup original
    const backupFile = join(this.skillDir, "SKILL.md.backup");
    if (!existsSync(backupFile)) {
      copyFileSync(this.skillFile, backupFile);
    }

    // ─── Baseline ───────────────────────────────────────────────
    this.log("─── Baseline ───");
    const baseline = await this.runEvalRound(this.bestSkill);
    this.bestRate = baseline.overallRate;
    this.log(
      `Baseline success rate: ${(this.bestRate * 100).toFixed(0)}%\n`,
    );

    this.iterations.push({
      iteration: 0,
      timestamp: Date.now(),
      results: baseline.results,
      overallRate: this.bestRate,
      improved: false,
      action: "baseline",
      changes: "Initial baseline measurement",
    });
    this.saveHistory(this.iterations[0]);

    if (this.bestRate >= this.evalConfig.targetRate) {
      this.log(
        `Already at target (${(this.bestRate * 100).toFixed(0)}% >= ${(this.evalConfig.targetRate * 100).toFixed(0)}%). Done!`,
      );
      this.printSummary();
      return;
    }

    // ─── Optimization Loop ──────────────────────────────────────
    for (let i = 1; i <= this.evalConfig.maxIterations; i++) {
      this.log(`\n─── Iteration ${i}/${this.evalConfig.maxIterations} ───`);

      // Analyze failures from previous round
      const prevResults =
        this.iterations[this.iterations.length - 1].results;
      const failures = prevResults.filter((r) => !r.allPassed);

      if (failures.length === 0) {
        this.log("No failures to fix — already perfect!");
        break;
      }

      // Refine the skill
      this.log(`Refining skill based on ${failures.length} failures...`);
      let candidateSkill: string;
      try {
        candidateSkill = await this.refineSkill(
          this.bestSkill,
          failures,
          this.bestRate,
          i,
        );
      } catch (err: unknown) {
        this.log(`Refinement failed: ${(err as Error).message}`);
        continue;
      }

      if (!candidateSkill || candidateSkill.length < 50) {
        this.log("Refinement produced empty/tiny output — skipping");
        continue;
      }

      // Eval the candidate
      this.log("Evaluating refined skill...");
      const evalRound = await this.runEvalRound(candidateSkill);
      const improved = evalRound.overallRate > this.bestRate;
      const action = improved ? "keep" : "discard";

      this.log(
        `\n  Rate: ${(evalRound.overallRate * 100).toFixed(0)}% (was ${(this.bestRate * 100).toFixed(0)}%) → ${action.toUpperCase()}`,
      );

      const iterLog: IterationLog = {
        iteration: i,
        timestamp: Date.now(),
        results: evalRound.results,
        overallRate: evalRound.overallRate,
        improved,
        action,
        changes: improved
          ? `Improved from ${(this.bestRate * 100).toFixed(0)}% to ${(evalRound.overallRate * 100).toFixed(0)}%`
          : `No improvement (${(evalRound.overallRate * 100).toFixed(0)}% vs ${(this.bestRate * 100).toFixed(0)}%)`,
      };
      this.iterations.push(iterLog);
      this.saveHistory(iterLog);

      if (improved) {
        this.bestRate = evalRound.overallRate;
        this.bestSkill = candidateSkill;
        writeFileSync(this.skillFile, candidateSkill);
        this.log(`  Saved improved SKILL.md`);

        // Save versioned backup
        const versionFile = join(
          this.skillDir,
          `SKILL.v${i}.md`,
        );
        writeFileSync(versionFile, candidateSkill);
      }

      if (this.bestRate >= this.evalConfig.targetRate) {
        this.log(
          `\nTarget reached! ${(this.bestRate * 100).toFixed(0)}% >= ${(this.evalConfig.targetRate * 100).toFixed(0)}%`,
        );
        break;
      }
    }

    this.printSummary();
  }

  private saveHistory(entry: IterationLog): void {
    const summary = {
      iteration: entry.iteration,
      timestamp: entry.timestamp,
      overallRate: entry.overallRate,
      action: entry.action,
      changes: entry.changes,
      passedTests: entry.results.filter((r) => r.allPassed).length,
      totalTests: entry.results.length,
    };
    appendFileSync(this.historyFile, JSON.stringify(summary) + "\n");
  }

  private printSummary(): void {
    const skillName = basename(this.skillDir);
    const baselineRate = this.iterations[0]?.overallRate ?? 0;
    const kept = this.iterations.filter((i) => i.action === "keep").length;
    const discarded = this.iterations.filter(
      (i) => i.action === "discard",
    ).length;

    this.log(`\n${"═".repeat(60)}`);
    this.log(`OPTIMIZATION COMPLETE: ${skillName}`);
    this.log(`${"═".repeat(60)}`);
    this.log(
      `  Baseline:     ${(baselineRate * 100).toFixed(0)}%`,
    );
    this.log(
      `  Final:        ${(this.bestRate * 100).toFixed(0)}%`,
    );
    this.log(
      `  Improvement:  +${((this.bestRate - baselineRate) * 100).toFixed(0)}pp`,
    );
    this.log(`  Iterations:   ${this.iterations.length - 1}`);
    this.log(`  Kept:         ${kept}`);
    this.log(`  Discarded:    ${discarded}`);
    this.log(
      `  Target:       ${(this.evalConfig.targetRate * 100).toFixed(0)}% ${this.bestRate >= this.evalConfig.targetRate ? "✓ REACHED" : "✗ NOT REACHED"}`,
    );
    this.log(`${"═".repeat(60)}\n`);
  }
}

// ─── CLI ──────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    console.log(`Skill Optimizer — iteratively refine SKILL.md files

Usage: npx tsx src/optimizer.ts <skill-dir> [options]

Arguments:
  skill-dir             Path to the skill directory (must contain SKILL.md and eval.json)

Options:
  --iterations N        Max optimization iterations (default: from eval.json or 10)
  --samples N           Test cases per iteration (default: from eval.json or 5)
  --target N            Target success rate 0-1 (default: from eval.json or 0.9)
  --model MODEL         Claude model to use (default: claude-sonnet-4-6)

Setup:
  1. Create a skill: mkdir -p ~/.config/kmac/assistant/skills/my-skill
  2. Write SKILL.md with your skill instructions
  3. Create eval.json with test cases and criteria:

     {
       "description": "What this skill does",
       "targetRate": 0.9,
       "maxIterations": 10,
       "samplesPerIteration": 5,
       "criteria": [
         "Output must follow X format",
         "Must include Y section"
       ],
       "testCases": [
         {
           "prompt": "A realistic user prompt for this skill",
           "criteria": ["Specific criteria for this test case"]
         }
       ]
     }

  4. Run: kmac skillopt ~/.config/kmac/assistant/skills/my-skill
`);
    process.exit(0);
  }

  if (args[0] === "init") {
    await initEvalConfig(args[1]);
    return;
  }

  const skillDir = args[0];
  if (!existsSync(skillDir)) {
    console.error(`Directory not found: ${skillDir}`);
    process.exit(1);
  }

  const overrides: Partial<EvalConfig> = {};
  for (let i = 1; i < args.length; i++) {
    switch (args[i]) {
      case "--iterations":
        overrides.maxIterations = parseInt(args[++i], 10);
        break;
      case "--samples":
        overrides.samplesPerIteration = parseInt(args[++i], 10);
        break;
      case "--target":
        overrides.targetRate = parseFloat(args[++i]);
        break;
      case "--model":
        overrides.model = args[++i];
        break;
    }
  }

  const optimizer = new SkillOptimizer(skillDir, overrides);
  await optimizer.optimize();
}

/** Generate a starter eval.json by reading the SKILL.md and asking Claude */
async function initEvalConfig(skillDir?: string): Promise<void> {
  if (!skillDir) {
    console.error("Usage: optimizer init <skill-dir>");
    process.exit(1);
  }

  const skillFile = join(skillDir, "SKILL.md");
  if (!existsSync(skillFile)) {
    console.error(`No SKILL.md found in ${skillDir}`);
    process.exit(1);
  }

  const evalFile = join(skillDir, "eval.json");
  if (existsSync(evalFile)) {
    console.log(`eval.json already exists in ${skillDir}`);
    process.exit(0);
  }

  console.log("Generating eval.json from SKILL.md...");

  const skill = readFileSync(skillFile, "utf-8");
  const client = new Anthropic();

  const resp = await client.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 4096,
    system: `You generate eval configurations for AI skills. Output valid JSON only, no markdown fences.`,
    messages: [
      {
        role: "user",
        content: `Read this SKILL.md and generate an eval.json with:
1. A description of what the skill does
2. 5-8 general criteria that ALL outputs should meet
3. 8-12 diverse test cases (realistic user prompts) with per-case criteria
4. Reasonable defaults for targetRate, maxIterations, samplesPerIteration

SKILL.md:
${skill}

Output the eval.json:`,
      },
    ],
  });

  const text = resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === "text")
    .map((b) => b.text)
    .join("");

  try {
    const cleaned = text.replace(/```json\s*|```\s*/g, "").trim();
    const config = JSON.parse(cleaned);
    writeFileSync(evalFile, JSON.stringify(config, null, 2));
    console.log(`Created ${evalFile}`);
    console.log(
      `  ${config.testCases?.length || 0} test cases, ${config.criteria?.length || 0} criteria`,
    );
    console.log(`  Edit to customize, then run: kmac skillopt ${skillDir}`);
  } catch {
    console.error("Failed to parse AI response. Raw output saved to eval.json.raw");
    writeFileSync(join(skillDir, "eval.json.raw"), text);
  }
}

main().catch((err) => {
  console.error("Fatal:", err.message || err);
  process.exit(1);
});
