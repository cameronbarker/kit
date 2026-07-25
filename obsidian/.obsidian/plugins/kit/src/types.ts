/** Shared plugin types. Feature-specific types live near their modules. */

export type ChatMode = "ask" | "edit";

export type ChatMessageKind =
  | "normal"
  | "streaming"
  | "proposal"
  | "applied"
  | "error";

export interface KitSettings {
  showHelloOnOpen: boolean;
  /** Empty means resolve `codex` on PATH. */
  codexBinary: string;
  defaultChatMode: ChatMode;
}

export type ChatRole = "user" | "assistant" | "system";

export interface ChatMessage {
  id: string;
  role: ChatRole;
  content: string;
  createdAt: number;
  kind?: ChatMessageKind;
  /** Live progress line while streaming. */
  statusLine?: string;
  mode?: ChatMode;
  /** Wall-clock start of the Codex run (ms since epoch). */
  startedAt?: number;
  /** Total run duration in milliseconds once finished. */
  durationMs?: number;
}

/** Side thread rooted at a main-lane parent message. */
export interface ChatThread {
  id: string;
  parentMessageId: string;
  messages: ChatMessage[];
  codexThreadId: string | null;
  createdAt: number;
  updatedAt: number;
}

/** Snapshot of the main-area tab (not the sidebar). */
export interface ActiveTabContext {
  viewType: string;
  title: string;
  filePath: string | null;
}

/** A vault document attached to the chat via @ mention. */
export interface ChatDocumentRef {
  path: string;
  basename: string;
}
