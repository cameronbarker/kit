import { ItemView, Notice, setIcon, WorkspaceLeaf } from "obsidian";
import { VIEW_TYPE_KIT_CHAT } from "../constants";
import type KitPlugin from "../main";
import { createChatMessage } from "../services/chat-service";
import type { ChatDocumentRef, ChatMessage } from "../types";
import { DocumentMentionModal } from "../ui/document-mention-modal";

export class KitChatView extends ItemView {
  plugin: KitPlugin;
  private messages: ChatMessage[] = [];
  private mentions: ChatDocumentRef[] = [];
  private listEl: HTMLElement | null = null;
  private contextEl: HTMLElement | null = null;
  private mentionsEl: HTMLElement | null = null;
  private inputEl: HTMLTextAreaElement | null = null;
  private sending = false;
  private mentionModalOpen = false;

  constructor(leaf: WorkspaceLeaf, plugin: KitPlugin) {
    super(leaf);
    this.plugin = plugin;
    this.messages = [
      createChatMessage(
        "assistant",
        "Hi — this is Kit chat. Type @ to attach a vault document.",
      ),
    ];
  }

  getViewType(): string {
    return VIEW_TYPE_KIT_CHAT;
  }

  getDisplayText(): string {
    return "Kit chat";
  }

  getIcon(): string {
    return "message-square";
  }

  async onOpen(): Promise<void> {
    this.render();
    this.registerEvent(
      this.app.workspace.on("active-leaf-change", (leaf) => {
        this.plugin.activeTabService.onActiveLeafChange(leaf);
        this.updateContextLabel();
      }),
    );
    this.registerEvent(
      this.app.workspace.on("file-open", () => {
        this.updateContextLabel();
      }),
    );
  }

  async onClose(): Promise<void> {
    this.contentEl.empty();
    this.listEl = null;
    this.contextEl = null;
    this.mentionsEl = null;
    this.inputEl = null;
  }

  private render(): void {
    const root = this.contentEl;
    root.empty();
    root.addClass("kit-chat");

    root.createEl("h2", { text: "Kit chat", cls: "kit-chat__title" });
    root.createEl("p", {
      text: "Talk with Kit AI from the sidebar. Type @ to mention a note.",
      cls: "kit-chat__subtitle",
    });

    this.contextEl = root.createDiv({ cls: "kit-chat__context" });
    this.updateContextLabel();

    this.listEl = root.createDiv({ cls: "kit-chat__messages" });
    this.renderMessages();

    const composer = root.createDiv({ cls: "kit-chat__composer" });
    this.mentionsEl = composer.createDiv({ cls: "kit-chat__mentions" });
    this.renderMentions();

    this.inputEl = composer.createEl("textarea", {
      cls: "kit-chat__input",
      attr: {
        rows: "3",
        placeholder: "Message Kit… (@ to attach a doc)",
      },
    });

    const actions = composer.createDiv({ cls: "kit-chat__actions" });
    const mentionBtn = actions.createEl("button", {
      text: "@",
      cls: "kit-chat__mention-btn",
      attr: { type: "button", title: "Mention a document", "aria-label": "Mention a document" },
    });
    const sendBtn = actions.createEl("button", {
      text: "Send",
      cls: "mod-cta kit-chat__send",
      attr: { type: "button" },
    });

    this.registerDomEvent(mentionBtn, "click", () => {
      this.openDocumentMention();
    });

    this.registerDomEvent(sendBtn, "click", () => {
      void this.handleSend();
    });

    this.registerDomEvent(this.inputEl, "keydown", (event: KeyboardEvent) => {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        void this.handleSend();
      }
    });

    this.registerDomEvent(this.inputEl, "input", () => {
      this.maybeOpenMentionFromAt();
    });
  }

  private updateContextLabel(): void {
    if (!this.contextEl) return;

    const context = this.plugin.activeTabService.getContext();
    this.contextEl.empty();
    this.contextEl.createEl("span", {
      text: "Looking at",
      cls: "kit-chat__context-label",
    });

    if (!context) {
      this.contextEl.createEl("span", {
        text: "No main tab",
        cls: "kit-chat__context-value kit-chat__context-value--empty",
      });
      return;
    }

    this.contextEl.createEl("span", {
      text: context.filePath ?? context.title,
      cls: "kit-chat__context-value",
      attr: {
        title: `${context.viewType}${context.filePath ? ` · ${context.filePath}` : ""}`,
      },
    });
  }

  private renderMentions(): void {
    if (!this.mentionsEl) return;
    this.mentionsEl.empty();

    if (this.mentions.length === 0) {
      this.mentionsEl.addClass("kit-chat__mentions--empty");
      return;
    }

    this.mentionsEl.removeClass("kit-chat__mentions--empty");

    for (const doc of this.mentions) {
      const chip = this.mentionsEl.createDiv({ cls: "kit-chat__chip" });
      chip.createEl("span", {
        text: `@${doc.basename}`,
        cls: "kit-chat__chip-label",
        attr: { title: doc.path },
      });
      const removeBtn = chip.createEl("button", {
        text: "×",
        cls: "kit-chat__chip-remove",
        attr: {
          type: "button",
          title: `Remove ${doc.path}`,
          "aria-label": `Remove ${doc.path}`,
        },
      });
      this.registerDomEvent(removeBtn, "click", () => {
        this.removeMention(doc.path);
      });
    }
  }

  private renderMessages(): void {
    if (!this.listEl) return;
    this.listEl.empty();

    for (const message of this.messages) {
      const bubble = this.listEl.createDiv({
        cls: `kit-chat__bubble kit-chat__bubble--${message.role}`,
      });

      const header = bubble.createDiv({ cls: "kit-chat__bubble-header" });
      header.createEl("span", {
        text: message.role === "user" ? "You" : "Kit",
        cls: "kit-chat__role",
      });

      const copyBtn = header.createEl("button", {
        cls: "kit-chat__copy",
        attr: {
          type: "button",
          title: "Copy message",
          "aria-label": "Copy message",
        },
      });
      setIcon(copyBtn, "copy");
      this.registerDomEvent(copyBtn, "click", () => {
        void this.copyMessage(message.content);
      });

      bubble.createEl("p", {
        text: message.content,
        cls: "kit-chat__content",
      });
    }

    this.listEl.scrollTop = this.listEl.scrollHeight;
  }

  private async copyMessage(content: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(content);
      new Notice("Copied message");
    } catch {
      new Notice("Could not copy message");
    }
  }

  private maybeOpenMentionFromAt(): void {
    if (!this.inputEl || this.mentionModalOpen) return;

    const el = this.inputEl;
    const cursor = el.selectionStart ?? 0;
    const before = el.value.slice(0, cursor);
    if (!/(?:^|[\s])@$/.test(before)) return;

    el.value = el.value.slice(0, cursor - 1) + el.value.slice(cursor);
    el.selectionStart = el.selectionEnd = cursor - 1;
    this.openDocumentMention();
  }

  private openDocumentMention(): void {
    if (this.mentionModalOpen) return;
    this.mentionModalOpen = true;

    const modal = new DocumentMentionModal(
      this.app,
      this.mentions.map((doc) => doc.path),
      (file) => {
        this.addMention({ path: file.path, basename: file.basename });
      },
    );

    const onClose = modal.onClose.bind(modal);
    modal.onClose = () => {
      this.mentionModalOpen = false;
      onClose();
      window.setTimeout(() => this.inputEl?.focus(), 0);
    };

    modal.open();
  }

  private addMention(doc: ChatDocumentRef): void {
    if (this.mentions.some((existing) => existing.path === doc.path)) return;
    this.mentions.push(doc);
    this.renderMentions();
  }

  private removeMention(path: string): void {
    this.mentions = this.mentions.filter((doc) => doc.path !== path);
    this.renderMentions();
  }

  private async handleSend(): Promise<void> {
    if (!this.inputEl || this.sending) return;

    const text = this.inputEl.value.trim();
    if (!text) return;

    this.sending = true;
    this.inputEl.value = "";

    const mentionPrefix =
      this.mentions.length > 0
        ? `${this.mentions.map((doc) => `@${doc.path}`).join(" ")}\n`
        : "";
    this.messages.push(createChatMessage("user", `${mentionPrefix}${text}`));
    this.renderMessages();

    const activeTab = this.plugin.activeTabService.getContext();
    const mentions = [...this.mentions];

    try {
      const reply = await this.plugin.chatService.reply(
        this.messages,
        activeTab,
        mentions,
      );
      this.messages.push(reply);
      this.renderMessages();
    } finally {
      this.sending = false;
      this.inputEl.focus();
    }
  }
}
