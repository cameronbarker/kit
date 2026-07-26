import { App, Notice, TFile, normalizePath } from "obsidian";
import type { ChatConversation, ChatMessage, ChatThread } from "../types";

export const CHAT_HISTORY_FOLDER = "kit/chats";

export interface ChatConversationMeta {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  firstUserText: string;
  lastAssistantText: string;
  lastUserText: string;
  mentionLabels: string[];
  modes: Array<"ask" | "edit">;
  userMessageCount: number;
  assistantMessageCount: number;
  threadCount: number;
}

function isWelcome(content: string): boolean {
  return content.startsWith("Hi — this is Kit chat");
}

function cleanText(text: string): string {
  return text.trim().replace(/\s+/g, " ");
}

function truncatePreview(text: string, max = 220): string {
  const cleaned = cleanText(text);
  if (cleaned.length <= max) return cleaned;
  return `${cleaned.slice(0, max - 1)}…`;
}

function meaningfulMessages(messages: ChatMessage[]): ChatMessage[] {
  return messages.filter((m) => {
    const content = m.content.trim();
    if (!content) return false;
    if (m.role === "assistant" && isWelcome(content)) return false;
    return m.role === "user" || m.role === "assistant";
  });
}

export function toConversationMeta(
  conversation: ChatConversation,
): ChatConversationMeta {
  const messages = meaningfulMessages(conversation.mainMessages);
  const userMessages = messages.filter((m) => m.role === "user");
  const assistantMessages = messages.filter((m) => m.role === "assistant");
  const firstUser = userMessages[0];
  const lastUser = userMessages[userMessages.length - 1];
  const lastAssistant = assistantMessages[assistantMessages.length - 1];

  const mentionLabels: string[] = [];
  const seenMentions = new Set<string>();
  for (const msg of userMessages) {
    for (const doc of msg.mentions ?? []) {
      if (seenMentions.has(doc.path)) continue;
      seenMentions.add(doc.path);
      mentionLabels.push(doc.basename);
    }
  }

  const modeSet = new Set<"ask" | "edit">();
  for (const msg of userMessages) {
    if (msg.mode === "ask" || msg.mode === "edit") modeSet.add(msg.mode);
  }

  return {
    id: conversation.id,
    title: conversation.title,
    createdAt: conversation.createdAt,
    updatedAt: conversation.updatedAt,
    firstUserText: firstUser ? truncatePreview(firstUser.content, 280) : "",
    lastAssistantText: lastAssistant
      ? truncatePreview(lastAssistant.content, 280)
      : "",
    lastUserText:
      lastUser && lastUser.id !== firstUser?.id
        ? truncatePreview(lastUser.content, 200)
        : "",
    mentionLabels,
    modes: Array.from(modeSet),
    userMessageCount: userMessages.length,
    assistantMessageCount: assistantMessages.length,
    threadCount: conversation.threads.length,
  };
}

function isChatMessage(value: unknown): value is ChatMessage {
  if (!value || typeof value !== "object") return false;
  const msg = value as ChatMessage;
  return (
    typeof msg.id === "string" &&
    typeof msg.role === "string" &&
    typeof msg.content === "string" &&
    typeof msg.createdAt === "number"
  );
}

function isChatThread(value: unknown): value is ChatThread {
  if (!value || typeof value !== "object") return false;
  const thread = value as ChatThread;
  return (
    typeof thread.id === "string" &&
    typeof thread.parentMessageId === "string" &&
    Array.isArray(thread.messages) &&
    thread.messages.every(isChatMessage) &&
    (thread.codexThreadId === null || typeof thread.codexThreadId === "string") &&
    typeof thread.createdAt === "number" &&
    typeof thread.updatedAt === "number"
  );
}

function parseConversation(raw: unknown): ChatConversation | null {
  if (!raw || typeof raw !== "object") return null;
  const data = raw as Partial<ChatConversation>;
  if (
    typeof data.id !== "string" ||
    typeof data.title !== "string" ||
    typeof data.createdAt !== "number" ||
    typeof data.updatedAt !== "number" ||
    !Array.isArray(data.mainMessages) ||
    !data.mainMessages.every(isChatMessage) ||
    !(
      data.mainCodexThreadId === null ||
      typeof data.mainCodexThreadId === "string"
    ) ||
    !Array.isArray(data.threads) ||
    !data.threads.every(isChatThread)
  ) {
    return null;
  }
  return {
    id: data.id,
    title: data.title,
    createdAt: data.createdAt,
    updatedAt: data.updatedAt,
    mainMessages: data.mainMessages,
    mainCodexThreadId: data.mainCodexThreadId,
    threads: data.threads,
    applyCheckpoints: Array.isArray(data.applyCheckpoints)
      ? data.applyCheckpoints.filter((id): id is string => typeof id === "string")
      : [],
  };
}

export class ChatHistoryService {
  constructor(private readonly app: App) {}

  pathFor(id: string): string {
    return normalizePath(`${CHAT_HISTORY_FOLDER}/${id}.json`);
  }

  async ensureFolder(): Promise<void> {
    for (const part of ["kit", CHAT_HISTORY_FOLDER]) {
      const path = normalizePath(part);
      if (!(await this.app.vault.adapter.exists(path))) {
        await this.app.vault.createFolder(path);
      }
    }
  }

  async listConversations(): Promise<ChatConversationMeta[]> {
    await this.ensureFolder();
    const folder = normalizePath(CHAT_HISTORY_FOLDER);
    const listed = await this.app.vault.adapter.list(folder);
    const metas: ChatConversationMeta[] = [];

    for (const filePath of listed.files) {
      if (!filePath.endsWith(".json")) continue;
      const conversation = await this.readPath(filePath);
      if (!conversation) continue;
      metas.push(toConversationMeta(conversation));
    }

    return metas.sort((a, b) => b.updatedAt - a.updatedAt);
  }

  async load(id: string): Promise<ChatConversation | null> {
    return this.readPath(this.pathFor(id));
  }

  async save(conversation: ChatConversation): Promise<void> {
    await this.ensureFolder();
    const path = this.pathFor(conversation.id);
    const body = `${JSON.stringify(conversation, null, 2)}\n`;
    const existing = this.app.vault.getAbstractFileByPath(path);
    if (existing instanceof TFile) {
      await this.app.vault.modify(existing, body);
      return;
    }
    await this.app.vault.create(path, body);
  }

  async delete(id: string): Promise<void> {
    const path = this.pathFor(id);
    const existing = this.app.vault.getAbstractFileByPath(path);
    if (existing instanceof TFile) {
      await this.app.vault.delete(existing);
    }
    const checkpointDir = normalizePath(`${CHAT_HISTORY_FOLDER}/${id}`);
    if (await this.app.vault.adapter.exists(checkpointDir)) {
      await this.removeDirRecursive(checkpointDir);
    }
  }

  private async removeDirRecursive(dir: string): Promise<void> {
    const normalized = normalizePath(dir);
    if (!(await this.app.vault.adapter.exists(normalized))) return;
    const listed = await this.app.vault.adapter.list(normalized);
    for (const file of listed.files) {
      await this.app.vault.adapter.remove(normalizePath(file));
    }
    for (const folder of listed.folders) {
      await this.removeDirRecursive(normalizePath(folder));
    }
    await this.app.vault.adapter.rmdir(normalized, false);
  }

  private async readPath(path: string): Promise<ChatConversation | null> {
    const normalized = normalizePath(path);
    try {
      const existing = this.app.vault.getAbstractFileByPath(normalized);
      let raw: string;
      if (existing instanceof TFile) {
        raw = await this.app.vault.read(existing);
      } else if (await this.app.vault.adapter.exists(normalized)) {
        raw = await this.app.vault.adapter.read(normalized);
      } else {
        return null;
      }
      const parsed = parseConversation(JSON.parse(raw) as unknown);
      if (!parsed) {
        new Notice(`Kit chat history file is invalid: ${normalized}`);
        return null;
      }
      return parsed;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      new Notice(`Could not read Kit chat history: ${message}`);
      return null;
    }
  }
}
