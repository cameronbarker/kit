import type {
  ActiveTabContext,
  ChatDocumentRef,
  ChatMessage,
  ChatMessageKind,
  ChatMode,
} from "../types";
import {
  runCodexExec,
  type CodexStreamEvent,
} from "./codex-exec";

let messageSeq = 0;

export function createChatMessage(
  role: ChatMessage["role"],
  content: string,
  extras?: Partial<
    Pick<ChatMessage, "kind" | "statusLine" | "mode" | "startedAt" | "durationMs">
  >,
): ChatMessage {
  messageSeq += 1;
  return {
    id: `msg-${Date.now()}-${messageSeq}`,
    role,
    content,
    createdAt: Date.now(),
    ...extras,
  };
}

function formatActiveTab(context: ActiveTabContext | null): string {
  if (!context) return "No main tab detected.";
  if (context.filePath) {
    return `Active tab: ${context.filePath} (${context.viewType})`;
  }
  return `Active tab: ${context.title} (${context.viewType})`;
}

function formatMentions(documents: ChatDocumentRef[]): string {
  if (documents.length === 0) return "Mentions: none";
  return `Mentions: ${documents.map((doc) => doc.path).join(", ")}`;
}

const APPLY_PROMPT =
  "Apply the plan you proposed. Make the vault edits now. Do not expand scope.";

export interface ChatThreadContext {
  parent: ChatMessage;
  /** Up to two main-lane messages before the parent, for orientation. */
  mainExcerpt?: ChatMessage[];
}

export interface ChatTurnInput {
  mode: ChatMode;
  userText: string;
  history: ChatMessage[];
  activeTab: ActiveTabContext | null;
  mentions: ChatDocumentRef[];
  threadId: string | null;
  vaultPath: string;
  binary: string;
  signal?: AbortSignal;
  onEvent: (event: CodexStreamEvent) => void;
  threadContext?: ChatThreadContext;
}

export interface ChatTurnResult {
  threadId: string | null;
  finalText: string;
  kind: ChatMessageKind;
}

export interface ApplyPlanInput {
  threadId: string;
  vaultPath: string;
  binary: string;
  signal?: AbortSignal;
  onEvent: (event: CodexStreamEvent) => void;
}

function modeInstructions(mode: ChatMode): string {
  if (mode === "ask") {
    return [
      "Mode: ASK (read-only).",
      "Answer the user's question using vault context.",
      "Do not edit, create, or delete any files.",
      "Do not propose a write plan unless they ask how something could be changed.",
    ].join("\n");
  }

  return [
    "Mode: EDIT (plan only — do not write yet).",
    "Produce a concrete plan for the requested vault changes.",
    "List every file you would create or modify and summarize the edits.",
    "Do not apply the edits in this turn. Wait for an explicit apply instruction.",
  ].join("\n");
}

function formatRole(message: ChatMessage): string {
  return message.role === "user" ? "User" : "Kit";
}

function formatThreadContext(ctx: ChatThreadContext): string {
  const lines = [
    "You are in a side thread off the main Kit chat.",
    "Focus on the thread topic rooted at the parent message below.",
    `Parent (${formatRole(ctx.parent)}):\n${ctx.parent.content}`,
  ];

  if (ctx.mainExcerpt && ctx.mainExcerpt.length > 0) {
    const excerpt = ctx.mainExcerpt
      .map((m) => `${formatRole(m)}: ${m.content}`)
      .join("\n\n");
    lines.push(`Main chat excerpt (before parent):\n${excerpt}`);
  }

  return lines.join("\n\n");
}

function buildPrompt(input: ChatTurnInput): string {
  const recent = input.history
    .filter((m) => m.role === "user" || m.role === "assistant")
    .slice(-8)
    .map((m) => `${formatRole(m)}: ${m.content}`)
    .join("\n\n");

  return [
    "You are Kit's vault assistant, running inside an Obsidian vault.",
    `Working directory is the vault root: ${input.vaultPath}`,
    modeInstructions(input.mode),
    input.threadContext ? formatThreadContext(input.threadContext) : "",
    formatActiveTab(input.activeTab),
    formatMentions(input.mentions),
    recent
      ? `${input.threadContext ? "Thread" : "Recent"} chat:\n${recent}`
      : "",
    `User request:\n${input.userText}`,
  ]
    .filter(Boolean)
    .join("\n\n");
}

/**
 * Codex-backed chat. Ask is read-only; Edit plans then Apply writes.
 */
export class ChatService {
  async startTurn(input: ChatTurnInput): Promise<ChatTurnResult> {
    let threadId = input.threadId;
    let finalText = "";

    await runCodexExec({
      binary: input.binary,
      vaultPath: input.vaultPath,
      prompt: buildPrompt(input),
      sandbox: "read-only",
      threadId,
      signal: input.signal,
      onEvent: (event) => {
        if (event.type === "thread.started") {
          threadId = event.threadId;
        }
        if (event.type === "agent_text") {
          finalText = event.replace
            ? event.text
            : `${finalText}${event.text}`;
        }
        input.onEvent(event);
      },
    });

    if (!finalText.trim()) {
      finalText =
        input.mode === "edit"
          ? "Plan ready. Review it, then click Apply to write changes."
          : "(No reply text from Codex.)";
    }

    return {
      threadId,
      finalText: finalText.trim(),
      kind: input.mode === "edit" ? "proposal" : "normal",
    };
  }

  async applyPlan(input: ApplyPlanInput): Promise<ChatTurnResult> {
    let threadId: string | null = input.threadId;
    let finalText = "";

    await runCodexExec({
      binary: input.binary,
      vaultPath: input.vaultPath,
      prompt: APPLY_PROMPT,
      sandbox: "workspace-write",
      threadId: input.threadId,
      signal: input.signal,
      onEvent: (event) => {
        if (event.type === "thread.started") {
          threadId = event.threadId;
        }
        if (event.type === "agent_text") {
          finalText = event.replace
            ? event.text
            : `${finalText}${event.text}`;
        }
        input.onEvent(event);
      },
    });

    if (!finalText.trim()) {
      finalText = "Applied the planned vault edits.";
    }

    return {
      threadId,
      finalText: finalText.trim(),
      kind: "applied",
    };
  }
}
