import { App, Modal, Notice, setIcon } from "obsidian";
import type { ChatConversationMeta } from "../services/chat-history-service";

function formatUpdatedAt(updatedAt: number): string {
  return new Date(updatedAt).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function formatStats(item: ChatConversationMeta): string {
  const turns =
    item.userMessageCount === 1
      ? "1 turn"
      : `${item.userMessageCount} turns`;
  const replies =
    item.assistantMessageCount === 1
      ? "1 reply"
      : `${item.assistantMessageCount} replies`;
  const parts = [turns, replies];
  if (item.threadCount === 1) parts.push("1 thread");
  else if (item.threadCount > 1) parts.push(`${item.threadCount} threads`);
  if (item.modes.length > 0) {
    parts.push(item.modes.map((m) => (m === "edit" ? "Edit" : "Ask")).join("/"));
  }
  parts.push(formatUpdatedAt(item.updatedAt));
  return parts.join(" · ");
}

export class ChatHistoryModal extends Modal {
  private items: ChatConversationMeta[];
  private readonly onOpenChat: (id: string) => void;
  private readonly onDeleteChat: (id: string) => Promise<void>;
  private listEl: HTMLElement | null = null;

  constructor(
    app: App,
    items: ChatConversationMeta[],
    onOpenChat: (id: string) => void,
    onDeleteChat: (id: string) => Promise<void>,
  ) {
    super(app);
    this.items = items;
    this.onOpenChat = onOpenChat;
    this.onDeleteChat = onDeleteChat;
  }

  onOpen(): void {
    this.setTitle("Chat history");
    this.modalEl.addClass("kit-chat-history-modal");
    this.renderList();
  }

  private renderList(): void {
    const { contentEl } = this;
    contentEl.empty();

    if (this.items.length === 0) {
      contentEl.createEl("p", {
        text: "No saved chats yet.",
        cls: "kit-chat-history-modal__empty",
      });
      return;
    }

    this.listEl = contentEl.createDiv({ cls: "kit-chat-history-modal__list" });
    for (const item of this.items) {
      this.renderRow(item);
    }
  }

  private renderRow(item: ChatConversationMeta): void {
    if (!this.listEl) return;

    const row = this.listEl.createDiv({ cls: "kit-chat-history-modal__row" });
    const openBtn = row.createEl("button", {
      cls: "kit-chat-history-modal__open",
      attr: {
        type: "button",
        title: `Open “${item.title}”`,
        "aria-label": `Open “${item.title}”`,
      },
    });

    openBtn.createEl("span", {
      text: item.title || "New chat",
      cls: "kit-chat-history-modal__title",
    });

    if (item.firstUserText) {
      const block = openBtn.createDiv({
        cls: "kit-chat-history-modal__snippet",
      });
      block.createEl("span", {
        text: "You",
        cls: "kit-chat-history-modal__snippet-label",
      });
      block.createEl("span", {
        text: item.firstUserText,
        cls: "kit-chat-history-modal__snippet-text",
      });
    }

    if (item.lastUserText) {
      const block = openBtn.createDiv({
        cls: "kit-chat-history-modal__snippet",
      });
      block.createEl("span", {
        text: "Later",
        cls: "kit-chat-history-modal__snippet-label",
      });
      block.createEl("span", {
        text: item.lastUserText,
        cls: "kit-chat-history-modal__snippet-text",
      });
    }

    if (item.lastAssistantText) {
      const block = openBtn.createDiv({
        cls: "kit-chat-history-modal__snippet",
      });
      block.createEl("span", {
        text: "Kit",
        cls: "kit-chat-history-modal__snippet-label",
      });
      block.createEl("span", {
        text: item.lastAssistantText,
        cls: "kit-chat-history-modal__snippet-text",
      });
    }

    if (item.mentionLabels.length > 0) {
      openBtn.createEl("span", {
        text: `@ ${item.mentionLabels.join(", ")}`,
        cls: "kit-chat-history-modal__mentions",
        attr: { title: item.mentionLabels.join(", ") },
      });
    }

    openBtn.createEl("span", {
      text: formatStats(item),
      cls: "kit-chat-history-modal__meta",
    });

    openBtn.addEventListener("click", () => {
      this.close();
      this.onOpenChat(item.id);
    });

    const deleteBtn = row.createEl("button", {
      cls: "kit-chat-history-modal__delete",
      attr: {
        type: "button",
        title: `Delete “${item.title}”`,
        "aria-label": `Delete “${item.title}”`,
      },
    });
    setIcon(deleteBtn, "trash-2");
    deleteBtn.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      void this.confirmAndDelete(item);
    });
  }

  private async confirmAndDelete(item: ChatConversationMeta): Promise<void> {
    const ok = window.confirm(
      `Delete chat “${item.title}”? This cannot be undone.`,
    );
    if (!ok) return;

    try {
      await this.onDeleteChat(item.id);
      this.items = this.items.filter((entry) => entry.id !== item.id);
      this.renderList();
      new Notice("Chat deleted.");
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      new Notice(`Could not delete chat: ${message}`);
    }
  }
}
