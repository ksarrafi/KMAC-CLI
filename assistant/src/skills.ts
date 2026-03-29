import { readFileSync, readdirSync, existsSync, mkdirSync } from "node:fs";
import { join, basename } from "node:path";
import type { Skill, AssistantConfig } from "./types.js";

/**
 * Skills are markdown files (SKILL.md) in the skills directory.
 * They get injected into the system prompt to give the assistant
 * specialized knowledge and behaviors.
 *
 * Directory structure:
 *   ~/.config/kmac/assistant/skills/
 *     coding/SKILL.md
 *     devops/SKILL.md
 *     writing/SKILL.md
 *
 * Also supports workspace-level skills via AGENTS.md in the working directory.
 */
export class SkillsLoader {
  private skillsDir: string;
  private skills: Skill[] = [];

  constructor(config: AssistantConfig) {
    this.skillsDir = config.skillsDir;
    mkdirSync(this.skillsDir, { recursive: true });
    this.load();
  }

  load(): void {
    this.skills = [];

    if (!existsSync(this.skillsDir)) return;

    const entries = readdirSync(this.skillsDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory()) {
        const skillFile = join(this.skillsDir, entry.name, "SKILL.md");
        if (existsSync(skillFile)) {
          try {
            const content = readFileSync(skillFile, "utf-8");
            this.skills.push({
              name: entry.name,
              path: skillFile,
              content,
            });
          } catch { /* skip unreadable */ }
        }
      } else if (entry.name.endsWith(".md") && entry.isFile()) {
        try {
          const content = readFileSync(join(this.skillsDir, entry.name), "utf-8");
          this.skills.push({
            name: basename(entry.name, ".md"),
            path: join(this.skillsDir, entry.name),
            content,
          });
        } catch { /* skip */ }
      }
    }
  }

  getSkills(): Skill[] {
    return this.skills;
  }

  /**
   * Load workspace-level prompt files (AGENTS.md, SOUL.md, TOOLS.md)
   * from a directory, similar to OpenClaw's workspace prompt injection.
   */
  loadWorkspacePrompts(dir: string): string[] {
    const prompts: string[] = [];
    const files = ["AGENTS.md", "SOUL.md", "TOOLS.md"];
    for (const file of files) {
      const path = join(dir, file);
      if (existsSync(path)) {
        try {
          prompts.push(readFileSync(path, "utf-8"));
        } catch { /* skip */ }
      }
    }
    return prompts;
  }

  /**
   * Build the skills section for the system prompt.
   */
  buildSkillsPrompt(): string {
    if (this.skills.length === 0) return "";

    const sections = this.skills.map(
      (s) => `## Skill: ${s.name}\n\n${s.content}`,
    );

    return `\n\n---\n# Active Skills\n\n${sections.join("\n\n---\n\n")}`;
  }
}
