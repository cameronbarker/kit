import { spawn, type ChildProcess } from "child_process";
import { existsSync } from "fs";
import { homedir } from "os";
import { delimiter, isAbsolute, join } from "path";

export type CodexSandbox = "read-only" | "workspace-write";

export type CodexStreamEvent =
  | { type: "thread.started"; threadId: string }
  | { type: "turn.started" }
  | { type: "turn.completed" }
  | { type: "turn.failed"; message: string }
  | { type: "error"; message: string }
  | { type: "status"; message: string }
  | { type: "agent_text"; text: string; replace?: boolean }
  | { type: "exit"; code: number | null; stderr: string };

export interface RunCodexExecOptions {
  binary: string;
  vaultPath: string;
  prompt: string;
  sandbox: CodexSandbox;
  /** Resume an existing Codex thread when set. */
  threadId?: string | null;
  signal?: AbortSignal;
  onEvent: (event: CodexStreamEvent) => void;
}

/**
 * Obsidian's GUI PATH is often minimal (no Homebrew /usr/local/bin).
 * Search common install locations and augment PATH for child processes.
 */
function candidatePathDirs(): string[] {
  const home = homedir();
  return [
    "/usr/local/bin",
    "/opt/homebrew/bin",
    join(home, ".local", "bin"),
    join(home, ".cargo", "bin"),
    join(home, ".bin"),
    "/usr/bin",
    "/bin",
  ];
}

function expandUserPath(path: string): string {
  if (path === "~") return homedir();
  if (path.startsWith("~/")) return join(homedir(), path.slice(2));
  return path;
}

function augmentedEnv(): NodeJS.ProcessEnv {
  const existing = process.env.PATH ?? "";
  const merged = [
    ...candidatePathDirs(),
    ...existing.split(delimiter).filter(Boolean),
  ];
  const unique = [...new Set(merged)];
  return { ...process.env, PATH: unique.join(delimiter) };
}

/** Resolve a usable absolute path when possible (GUI apps often lack shell PATH). */
export function resolveBinary(binary: string): string {
  const trimmed = binary.trim();
  const nameOrPath = trimmed.length > 0 ? trimmed : "codex";
  const expanded = expandUserPath(nameOrPath);

  if (isAbsolute(expanded)) {
    return expanded;
  }

  // Relative path from settings (contains a slash) — leave as-is.
  if (expanded.includes("/") || expanded.includes("\\")) {
    return expanded;
  }

  for (const dir of [
    ...candidatePathDirs(),
    ...(process.env.PATH ?? "").split(delimiter).filter(Boolean),
  ]) {
    const candidate = join(dir, expanded);
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return expanded;
}

function buildArgs(options: RunCodexExecOptions): string[] {
  const args: string[] = ["--ask-for-approval", "never"];

  if (options.threadId) {
    args.push(
      "exec",
      "resume",
      "--json",
      "--skip-git-repo-check",
      "-c",
      `sandbox_mode="${options.sandbox}"`,
      options.threadId,
      options.prompt,
    );
    return args;
  }

  args.push(
    "exec",
    "--json",
    "--cd",
    options.vaultPath,
    "--sandbox",
    options.sandbox,
    "--skip-git-repo-check",
    options.prompt,
  );
  return args;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function itemLabel(item: Record<string, unknown>): string | null {
  const itemType = typeof item.type === "string" ? item.type : null;
  if (!itemType) return null;

  if (itemType === "command_execution") {
    const command = typeof item.command === "string" ? item.command : "";
    const short = command.length > 80 ? `${command.slice(0, 77)}…` : command;
    return short ? `Running: ${short}` : "Running command…";
  }

  if (itemType === "file_change" || itemType === "FileChange") {
    const path =
      (typeof item.path === "string" && item.path) ||
      (typeof item.file === "string" && item.file) ||
      "";
    return path ? `File: ${path}` : "Updating files…";
  }

  if (itemType === "agent_message" || itemType === "AgentMessage") {
    return "Writing reply…";
  }

  if (itemType === "reasoning" || itemType === "Reasoning") {
    return "Thinking…";
  }

  return itemType;
}

function agentTextFromItem(item: Record<string, unknown>): string | null {
  const itemType = typeof item.type === "string" ? item.type : "";
  if (
    itemType !== "agent_message" &&
    itemType !== "AgentMessage" &&
    itemType !== "message"
  ) {
    return null;
  }

  if (typeof item.text === "string" && item.text.trim()) {
    return item.text;
  }
  if (typeof item.message === "string" && item.message.trim()) {
    return item.message;
  }
  return null;
}

function emitFromJsonLine(
  line: string,
  onEvent: (event: CodexStreamEvent) => void,
): void {
  let parsed: unknown;
  try {
    parsed = JSON.parse(line);
  } catch {
    return;
  }

  const obj = asRecord(parsed);
  if (!obj) return;

  const type = typeof obj.type === "string" ? obj.type : null;
  if (!type) return;

  if (type === "thread.started") {
    const threadId =
      (typeof obj.thread_id === "string" && obj.thread_id) ||
      (typeof obj.threadId === "string" && obj.threadId) ||
      "";
    if (threadId) {
      onEvent({ type: "thread.started", threadId });
    }
    return;
  }

  if (type === "turn.started") {
    onEvent({ type: "turn.started" });
    onEvent({ type: "status", message: "Working…" });
    return;
  }

  if (type === "turn.completed") {
    onEvent({ type: "turn.completed" });
    return;
  }

  if (type === "turn.failed") {
    const message =
      (typeof obj.message === "string" && obj.message) ||
      (typeof obj.error === "string" && obj.error) ||
      "Turn failed";
    onEvent({ type: "turn.failed", message });
    return;
  }

  if (type === "error") {
    const message =
      (typeof obj.message === "string" && obj.message) ||
      JSON.stringify(obj);
    onEvent({ type: "error", message });
    return;
  }

  if (type === "item.started" || type === "item.completed") {
    const item = asRecord(obj.item);
    if (!item) return;

    const label = itemLabel(item);
    if (label) {
      onEvent({ type: "status", message: label });
    }

    if (type === "item.completed") {
      const text = agentTextFromItem(item);
      if (text) {
        onEvent({ type: "agent_text", text, replace: true });
      }
    }
  }
}

/**
 * Run Codex non-interactively and stream JSONL events.
 * Approval flag is placed before `exec` (CLI quirk on 0.145+).
 */
export function runCodexExec(options: RunCodexExecOptions): Promise<void> {
  const binary = resolveBinary(options.binary);
  const args = buildArgs(options);
  const env = augmentedEnv();

  return new Promise((resolve, reject) => {
    let child: ChildProcess;
    try {
      child = spawn(binary, args, {
        cwd: options.vaultPath,
        env,
        // Codex treats an open stdin pipe as "read more prompt" and hangs.
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
      return;
    }

    let stdoutBuffer = "";
    let stderr = "";
    let settled = false;

    const settle = (fn: () => void) => {
      if (settled) return;
      settled = true;
      fn();
    };

    const onAbort = () => {
      try {
        child.kill("SIGTERM");
      } catch {
        // ignore
      }
      // Escalating kill if Codex ignores SIGTERM.
      setTimeout(() => {
        if (settled) return;
        try {
          child.kill("SIGKILL");
        } catch {
          // ignore
        }
      }, 1500);
    };

    if (options.signal) {
      if (options.signal.aborted) {
        onAbort();
      } else {
        options.signal.addEventListener("abort", onAbort, { once: true });
      }
    }

    if (!child.stdout || !child.stderr) {
      settle(() => reject(new Error("Codex spawn missing stdout/stderr pipes")));
      return;
    }

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");

    child.stdout.on("data", (chunk: string) => {
      stdoutBuffer += chunk;
      const lines = stdoutBuffer.split("\n");
      stdoutBuffer = lines.pop() ?? "";
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        emitFromJsonLine(trimmed, options.onEvent);
      }
    });

    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
      const line = chunk.trim();
      if (line) {
        // Surface progress hints (Codex often writes human progress to stderr).
        const first = line.split("\n").find((l) => l.trim())?.trim();
        if (
          first &&
          !first.startsWith("{") &&
          !first.includes("Reading additional input from stdin")
        ) {
          options.onEvent({ type: "status", message: first.slice(0, 120) });
        }
      }
    });

    child.on("error", (error) => {
      options.signal?.removeEventListener("abort", onAbort);
      settle(() => reject(error));
    });

    child.on("close", (code) => {
      options.signal?.removeEventListener("abort", onAbort);

      const remainder = stdoutBuffer.trim();
      if (remainder) {
        emitFromJsonLine(remainder, options.onEvent);
      }

      options.onEvent({ type: "exit", code, stderr: stderr.trim() });

      if (options.signal?.aborted) {
        settle(() => reject(new DOMException("Aborted", "AbortError")));
        return;
      }

      if (code !== 0) {
        const detail = stderr.trim() || `Codex exited with code ${code}`;
        settle(() => reject(new Error(detail)));
        return;
      }

      settle(() => resolve());
    });
  });
}

/** Best-effort check that the Codex binary runs. */
export async function checkCodexBinary(binary: string): Promise<{
  ok: boolean;
  version?: string;
  resolvedPath?: string;
  error?: string;
}> {
  const resolved = resolveBinary(binary);
  const env = augmentedEnv();

  if (!existsSync(resolved) && !resolved.includes("/") && resolved === "codex") {
    return {
      ok: false,
      error:
        "spawn codex ENOENT — set Kit settings → Codex binary to /usr/local/bin/codex (or your install path)",
    };
  }

  return new Promise((resolve) => {
    let child: ChildProcess;
    try {
      child = spawn(resolved, ["--version"], {
        env,
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (error) {
      resolve({
        ok: false,
        resolvedPath: resolved,
        error: error instanceof Error ? error.message : String(error),
      });
      return;
    }

    if (!child.stdout || !child.stderr) {
      resolve({
        ok: false,
        resolvedPath: resolved,
        error: "Codex spawn missing stdout/stderr pipes",
      });
      return;
    }

    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (c: string) => {
      stdout += c;
    });
    child.stderr.on("data", (c: string) => {
      stderr += c;
    });
    child.on("error", (error) => {
      resolve({
        ok: false,
        resolvedPath: resolved,
        error: error.message,
      });
    });
    child.on("close", (code) => {
      if (code === 0) {
        resolve({
          ok: true,
          resolvedPath: resolved,
          version: (stdout || stderr).trim(),
        });
        return;
      }
      resolve({
        ok: false,
        resolvedPath: resolved,
        error: (stderr || stdout || `exit ${code}`).trim(),
      });
    });
  });
}
