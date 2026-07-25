/** Shared plugin types. Feature-specific types live near their modules. */

export interface KitSettings {
  showHelloOnOpen: boolean;
}

export type ChatRole = "user" | "assistant" | "system";

export interface ChatMessage {
  id: string;
  role: ChatRole;
  content: string;
  createdAt: number;
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
