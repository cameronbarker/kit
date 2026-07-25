import type {
  ActiveTabContext,
  ChatDocumentRef,
  ChatMessage,
} from "../types";

let messageSeq = 0;

export function createChatMessage(
  role: ChatMessage["role"],
  content: string,
): ChatMessage {
  messageSeq += 1;
  return {
    id: `msg-${Date.now()}-${messageSeq}`,
    role,
    content,
    createdAt: Date.now(),
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

/**
 * Placeholder chat backend. Swap this for a real model/provider later.
 */
export class ChatService {
  async reply(
    history: ChatMessage[],
    activeTab: ActiveTabContext | null,
    mentions: ChatDocumentRef[],
  ): Promise<ChatMessage> {
    void history;
    return createChatMessage(
      "assistant",
      [
        "Chat is scaffolded. Wire an AI provider here next.",
        formatActiveTab(activeTab),
        formatMentions(mentions),
      ].join("\n"),
    );
  }
}
