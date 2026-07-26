import { spawn } from "child_process";
import { existsSync } from "fs";
import { isAbsolute, join } from "path";
import { augmentedEnv, resolveBinary } from "./codex-exec";

const DEFAULT_TIMEOUT_MS = 8_000;

export interface QmdHit {
  path: string;
  absolutePath: string;
  title?: string;
  snippet?: string;
  score?: number;
  collection?: string;
}

export interface QmdRetrievalResult {
  available: boolean;
  hits: QmdHit[];
  warning?: string;
}

export interface QmdRetrieveOptions {
  query: string;
  vaultPath: string;
  binary?: string;
  index?: string;
  limit?: number;
  signal?: AbortSignal;
  timeoutMs?: number;
}

function firstPresent(
  hit: Record<string, unknown>,
  ...keys: string[]
): string | undefined {
  for (const key of keys) {
    const value = hit[key];
    if (value == null) continue;
    if (typeof value === "string") {
      const trimmed = value.trim();
      if (trimmed.length > 0) return trimmed;
      continue;
    }
    if (typeof value === "number" || typeof value === "boolean") {
      return String(value);
    }
  }
  return undefined;
}

function numeric(value: unknown): number | undefined {
  if (value == null) return undefined;
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : undefined;
}

function extractHitList(raw: unknown): Record<string, unknown>[] {
  if (Array.isArray(raw)) {
    return raw.filter(
      (item): item is Record<string, unknown> =>
        Boolean(item) && typeof item === "object",
    );
  }
  if (raw && typeof raw === "object") {
    const obj = raw as Record<string, unknown>;
    const nested = obj.results ?? obj.hits ?? obj.documents;
    if (Array.isArray(nested)) {
      return nested.filter(
        (item): item is Record<string, unknown> =>
          Boolean(item) && typeof item === "object",
      );
    }
  }
  return [];
}

function resolveHitPath(rawPath: string, vaultPath: string): string {
  const trimmed = rawPath.trim();
  if (!trimmed) return trimmed;

  if (isAbsolute(trimmed)) {
    return trimmed;
  }

  const underVault = join(vaultPath.replace(/\/$/, ""), trimmed);
  if (existsSync(underVault)) {
    return underVault;
  }

  // Common Kit layout: vault is .../obsidian and qmd returns obsidian/foo.md
  // relative to the Kit repo. Try stripping a leading "obsidian/" segment.
  const withoutObsidian = trimmed.replace(/^obsidian\//, "");
  if (withoutObsidian !== trimmed) {
    const alt = join(vaultPath.replace(/\/$/, ""), withoutObsidian);
    if (existsSync(alt)) return alt;
  }

  return underVault;
}

function normalizeHit(
  hit: Record<string, unknown>,
  vaultPath: string,
): QmdHit | null {
  const path = firstPresent(hit, "path", "filepath", "file", "filename", "id");
  if (!path) return null;

  const absolutePath = resolveHitPath(path, vaultPath);
  return {
    path,
    absolutePath,
    title: firstPresent(hit, "title", "heading", "name"),
    snippet: firstPresent(
      hit,
      "snippet",
      "text",
      "content",
      "excerpt",
      "preview",
    ),
    score: numeric(
      hit.score ?? hit.rrf_score ?? hit.rank_score ?? undefined,
    ),
    collection: firstPresent(hit, "collection", "collection_name"),
  };
}

/**
 * Local qmd hybrid query for Kit chat. Never throws for missing binary —
 * returns available: false so chat can continue.
 */
export async function retrieveQmd(
  options: QmdRetrieveOptions,
): Promise<QmdRetrievalResult> {
  const query = options.query.trim();
  if (!query) {
    return { available: false, hits: [], warning: "missing retrieval query" };
  }

  const binary = resolveBinary(options.binary?.trim() ? options.binary : "qmd");
  const limit =
    options.limit && options.limit > 0 ? Math.floor(options.limit) : 5;
  const index = options.index?.trim() || "kit";
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  const args = ["query", "--index", index, "--json", "-n", String(limit), query];

  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(binary, args, {
        env: augmentedEnv(),
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      resolve({
        available: false,
        hits: [],
        warning: message.includes("ENOENT")
          ? "qmd binary not found"
          : message,
      });
      return;
    }

    let stdout = "";
    let stderr = "";
    let settled = false;

    const finish = (result: QmdRetrievalResult) => {
      if (settled) return;
      settled = true;
      resolve(result);
    };

    const timer = setTimeout(() => {
      try {
        child.kill("SIGTERM");
      } catch {
        // ignore
      }
      finish({
        available: false,
        hits: [],
        warning: "qmd query timed out",
      });
    }, timeoutMs);

    const onAbort = () => {
      try {
        child.kill("SIGTERM");
      } catch {
        // ignore
      }
      clearTimeout(timer);
      finish({
        available: false,
        hits: [],
        warning: "qmd query aborted",
      });
    };

    if (options.signal) {
      if (options.signal.aborted) {
        onAbort();
        return;
      }
      options.signal.addEventListener("abort", onAbort, { once: true });
    }

    child.stdout?.on("data", (chunk: Buffer | string) => {
      stdout += chunk.toString();
    });
    child.stderr?.on("data", (chunk: Buffer | string) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      clearTimeout(timer);
      options.signal?.removeEventListener("abort", onAbort);
      const message = error.message || String(error);
      finish({
        available: false,
        hits: [],
        warning: message.includes("ENOENT")
          ? "qmd binary not found"
          : message,
      });
    });

    child.on("close", (code) => {
      clearTimeout(timer);
      options.signal?.removeEventListener("abort", onAbort);

      if (code !== 0) {
        finish({
          available: false,
          hits: [],
          warning:
            stderr.trim() ||
            (code == null ? "qmd query failed" : `qmd query exited ${code}`),
        });
        return;
      }

      try {
        const text = stdout.trim();
        const raw = text.length > 0 ? (JSON.parse(text) as unknown) : [];
        const hits = extractHitList(raw)
          .map((hit) => normalizeHit(hit, options.vaultPath))
          .filter((hit): hit is QmdHit => hit != null);
        finish({ available: true, hits });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        finish({
          available: false,
          hits: [],
          warning: `qmd returned invalid JSON: ${message}`,
        });
      }
    });
  });
}

export function formatRetrievalHits(hits: QmdHit[]): string {
  if (hits.length === 0) {
    return "Related notes from Kit retrieval (qmd): none.";
  }

  const lines = hits.map((hit) => {
    const title = hit.title ? ` ${hit.title} —` : "";
    const snippet = hit.snippet ? ` ${hit.snippet}` : "";
    const collection = hit.collection ? ` [${hit.collection}]` : "";
    return `- ${hit.absolutePath}${collection}:${title}${snippet}`.trimEnd();
  });

  return [
    "Related notes from Kit retrieval (qmd). Prefer these; read with your tools as needed:",
    ...lines,
  ].join("\n");
}
