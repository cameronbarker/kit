import {
  FileSystemAdapter,
  ItemView,
  Notice,
  Platform,
  setIcon,
  WorkspaceLeaf,
} from "obsidian";
import { VIEW_TYPE_KIT_CHAT } from "../constants";
import type KitPlugin from "../main";
import { createChatMessage } from "../services/chat-service";
import type { CodexStreamEvent } from "../services/codex-exec";
import { checkCodexBinary } from "../services/codex-exec";
import type {
  ChatDocumentRef,
  ChatMessage,
  ChatMode,
  ChatThread,
} from "../types";
import { DocumentMentionModal } from "../ui/document-mention-modal";

let threadSeq = 0;

export class KitChatView extends ItemView {
  plugin: KitPlugin;
  private mainMessages: ChatMessage[] = [];
  private mainCodexThreadId: string | null = null;
  private threads = new Map<string, ChatThread>();
  private activeThreadParentId: string | null = null;
  private mentions: ChatDocumentRef[] = [];
  private mode: ChatMode = "ask";
  private listEl: HTMLElement | null = null;
  private mentionsEl: HTMLElement | null = null;
  private threadChromeEl: HTMLElement | null = null;
  private inputEl: HTMLTextAreaElement | null = null;
  private modeAskBtn: HTMLButtonElement | null = null;
  private modeEditBtn: HTMLButtonElement | null = null;
  private sendBtn: HTMLButtonElement | null = null;
  private cancelBtn: HTMLButtonElement | null = null;
  private sending = false;
  private mentionModalOpen = false;
  private abortController: AbortController | null = null;
  private codexReady: boolean | null = null;
  private elapsedTimer: number | null = null;
  /** User message currently open for in-place edit. */
  private editingMessageId: string | null = null;
  /** Draft @ attachments while editing a user message. */
  private editingMentions: ChatDocumentRef[] = [];
  /** Message ids whose bodies are collapsed in the UI. */
  private collapsedMessageIds = new Set<string>();

  constructor(leaf: WorkspaceLeaf, plugin: KitPlugin) {
    super(leaf);
    this.plugin = plugin;
    this.mode = plugin.settings.defaultChatMode;
    this.mainMessages = [
      createChatMessage(
        "assistant",
        "Hi — this is Kit chat. Choose Ask or Edit, type @ to attach a vault document.",
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
      }),
    );
    void this.refreshCodexStatus();
  }

  async onClose(): Promise<void> {
    this.stopElapsedTimer();
    this.abortController?.abort();
    this.contentEl.empty();
    this.listEl = null;
    this.mentionsEl = null;
    this.threadChromeEl = null;
    this.inputEl = null;
    this.modeAskBtn = null;
    this.modeEditBtn = null;
    this.sendBtn = null;
    this.cancelBtn = null;
  }

  private inThread(): boolean {
    return this.activeThreadParentId !== null;
  }

  private activeMessages(): ChatMessage[] {
    if (!this.activeThreadParentId) return this.mainMessages;
    const thread = this.threads.get(this.activeThreadParentId);
    return thread?.messages ?? this.mainMessages;
  }

  private getActiveCodexThreadId(): string | null {
    if (!this.activeThreadParentId) return this.mainCodexThreadId;
    return this.threads.get(this.activeThreadParentId)?.codexThreadId ?? null;
  }

  private setActiveCodexThreadId(id: string | null): void {
    if (!this.activeThreadParentId) {
      this.mainCodexThreadId = id;
      return;
    }
    const thread = this.threads.get(this.activeThreadParentId);
    if (thread) {
      thread.codexThreadId = id;
      thread.updatedAt = Date.now();
    }
  }

  private replaceActiveMessages(messages: ChatMessage[]): void {
    if (!this.activeThreadParentId) {
      this.mainMessages = messages;
      return;
    }
    const thread = this.threads.get(this.activeThreadParentId);
    if (thread) {
      thread.messages = messages;
      thread.updatedAt = Date.now();
    }
  }

  private touchActiveThread(): void {
    if (!this.activeThreadParentId) return;
    const thread = this.threads.get(this.activeThreadParentId);
    if (thread) thread.updatedAt = Date.now();
  }

  private ensureThread(parentMessageId: string): ChatThread {
    const existing = this.threads.get(parentMessageId);
    if (existing) return existing;

    threadSeq += 1;
    const now = Date.now();
    const thread: ChatThread = {
      id: `thread-${now}-${threadSeq}`,
      parentMessageId,
      messages: [],
      codexThreadId: null,
      createdAt: now,
      updatedAt: now,
    };
    this.threads.set(parentMessageId, thread);
    return thread;
  }

  private parentMessage(): ChatMessage | null {
    if (!this.activeThreadParentId) return null;
    return (
      this.mainMessages.find((m) => m.id === this.activeThreadParentId) ?? null
    );
  }

  private mainExcerptBefore(parentId: string): ChatMessage[] {
    const index = this.mainMessages.findIndex((m) => m.id === parentId);
    if (index <= 0) return [];
    return this.mainMessages.slice(Math.max(0, index - 2), index);
  }

  private buildThreadContext() {
    const parent = this.parentMessage();
    if (!parent || !this.activeThreadParentId) return undefined;
    return {
      parent,
      mainExcerpt: this.mainExcerptBefore(parent.id),
    };
  }

  private openThread(parentMessageId: string): void {
    if (this.sending) return;
    const parent = this.mainMessages.find((m) => m.id === parentMessageId);
    if (!parent || parent.kind === "streaming") return;

    this.editingMessageId = null;
    this.editingMentions = [];
    this.ensureThread(parentMessageId);
    this.activeThreadParentId = parentMessageId;
    this.updateThreadChrome();
    this.renderMessages();
    this.updateActionButtons();
    this.inputEl?.focus();
  }

  private closeThread(): void {
    if (this.sending) return;
    this.editingMessageId = null;
    this.editingMentions = [];
    this.activeThreadParentId = null;
    this.updateThreadChrome();
    this.renderMessages();
    this.updateActionButtons();
  }

  private vaultPath(): string | null {
    const adapter = this.app.vault.adapter;
    if (adapter instanceof FileSystemAdapter) {
      return adapter.getBasePath();
    }
    return null;
  }

  private async refreshCodexStatus(): Promise<void> {
    if (!Platform.isDesktopApp) {
      this.codexReady = false;
      this.updateActionButtons();
      return;
    }

    const result = await checkCodexBinary(this.plugin.settings.codexBinary);
    this.codexReady = result.ok;
    if (!result.ok) {
      new Notice(
        `Codex not found. Set Kit settings → Codex binary (e.g. /usr/local/bin/codex).`,
      );
    }
    this.updateActionButtons();
  }

  private render(): void {
    const root = this.contentEl;
    root.empty();
    root.addClass("kit-chat");

    if (!Platform.isDesktopApp) {
      root.createEl("p", {
        text: "Codex chat requires the Obsidian desktop app.",
        cls: "kit-chat__subtitle",
      });
      return;
    }

    this.threadChromeEl = root.createDiv({ cls: "kit-chat__thread-chrome" });
    this.updateThreadChrome();

    this.listEl = root.createDiv({ cls: "kit-chat__messages" });
    this.renderMessages();

    const composer = root.createDiv({ cls: "kit-chat__composer" });
    this.mentionsEl = composer.createDiv({ cls: "kit-chat__mentions" });
    this.renderMentions();

    this.inputEl = composer.createEl("textarea", {
      cls: "kit-chat__input",
      attr: {
        rows: "3",
        placeholder: this.inThread()
          ? "Reply in thread… (@ to attach a doc)"
          : "Message Kit… (@ to attach a doc)",
      },
    });

    const toolbar = composer.createDiv({ cls: "kit-chat__toolbar" });

    const modeGroup = toolbar.createDiv({
      cls: "kit-chat__mode",
      attr: { role: "group", "aria-label": "Chat mode" },
    });
    this.modeAskBtn = modeGroup.createEl("button", {
      text: "Ask",
      cls: "kit-chat__mode-btn",
      attr: { type: "button" },
    });
    this.modeEditBtn = modeGroup.createEl("button", {
      text: "Edit",
      cls: "kit-chat__mode-btn",
      attr: { type: "button" },
    });
    this.syncModeButtons();

    const actions = toolbar.createDiv({ cls: "kit-chat__actions" });
    const mentionBtn = actions.createEl("button", {
      text: "@",
      cls: "kit-chat__mention-btn",
      attr: {
        type: "button",
        title: "Mention a document",
        "aria-label": "Mention a document",
      },
    });
    this.cancelBtn = actions.createEl("button", {
      text: "Stop",
      cls: "mod-warning kit-chat__stop",
      attr: {
        type: "button",
        title: "Stop the current Codex run",
        "aria-label": "Stop the current Codex run",
      },
    });
    this.sendBtn = actions.createEl("button", {
      text: "Send",
      cls: "mod-cta kit-chat__send",
      attr: { type: "button" },
    });

    this.registerDomEvent(this.modeAskBtn, "click", () => {
      this.setMode("ask");
    });
    this.registerDomEvent(this.modeEditBtn, "click", () => {
      this.setMode("edit");
    });
    this.registerDomEvent(mentionBtn, "click", () => {
      this.openDocumentMention();
    });
    this.registerDomEvent(this.cancelBtn, "click", () => {
      this.handleStop();
    });
    this.registerDomEvent(this.sendBtn, "click", () => {
      void this.handleSend();
    });
    this.registerDomEvent(this.inputEl, "keydown", (event: KeyboardEvent) => {
      if (event.key === "Escape" && this.sending) {
        event.preventDefault();
        this.handleStop();
        return;
      }
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        void this.handleSend();
      }
    });
    this.registerDomEvent(this.inputEl, "input", () => {
      this.maybeOpenMentionFromAt();
    });

    this.updateActionButtons();
  }

  private updateThreadChrome(): void {
    if (!this.threadChromeEl) return;
    this.threadChromeEl.empty();

    if (!this.inThread()) {
      this.threadChromeEl.addClass("kit-chat__thread-chrome--empty");
      return;
    }

    this.threadChromeEl.removeClass("kit-chat__thread-chrome--empty");
    const parent = this.parentMessage();

    const bar = this.threadChromeEl.createDiv({ cls: "kit-chat__thread-bar" });
    const backBtn = bar.createEl("button", {
      text: "Back",
      cls: "kit-chat__thread-back",
      attr: {
        type: "button",
        title: "Back to main chat",
        "aria-label": "Back to main chat",
      },
    });
    backBtn.disabled = this.sending;
    this.registerDomEvent(backBtn, "click", () => {
      this.closeThread();
    });

    bar.createEl("span", {
      text: "Thread",
      cls: "kit-chat__thread-label",
    });

    if (parent) {
      const preview =
        parent.content.length > 120
          ? `${parent.content.slice(0, 117)}…`
          : parent.content;
      this.threadChromeEl.createEl("p", {
        text: preview || "(empty message)",
        cls: "kit-chat__thread-parent-preview",
        attr: { title: parent.content },
      });
    }

    if (this.inputEl) {
      this.inputEl.placeholder = this.inThread()
        ? "Reply in thread… (@ to attach a doc)"
        : "Message Kit… (@ to attach a doc)";
    }
  }

  private setMode(mode: ChatMode): void {
    if (this.sending) return;
    this.mode = mode;
    this.syncModeButtons();
  }

  private syncModeButtons(): void {
    this.modeAskBtn?.toggleClass("is-active", this.mode === "ask");
    this.modeEditBtn?.toggleClass("is-active", this.mode === "edit");
    this.modeAskBtn?.setAttribute(
      "aria-pressed",
      this.mode === "ask" ? "true" : "false",
    );
    this.modeEditBtn?.setAttribute(
      "aria-pressed",
      this.mode === "edit" ? "true" : "false",
    );
  }

  private updateActionButtons(): void {
    const canSend = !this.sending && this.codexReady === true;
    if (this.sendBtn) {
      this.sendBtn.disabled = !canSend;
      this.sendBtn.toggleClass("is-hidden", this.sending);
    }
    if (this.cancelBtn) {
      this.cancelBtn.toggleClass("is-visible", this.sending);
      this.cancelBtn.disabled = !this.sending;
    }
    if (this.modeAskBtn) this.modeAskBtn.disabled = this.sending;
    if (this.modeEditBtn) this.modeEditBtn.disabled = this.sending;
    if (this.inputEl) this.inputEl.disabled = this.sending;
    this.updateThreadChrome();
  }

  private handleStop(): void {
    if (!this.sending || !this.abortController) return;

    const streaming = [...this.activeMessages()]
      .reverse()
      .find((m) => m.kind === "streaming");
    if (streaming) {
      streaming.statusLine = "Stopping…";
      this.renderMessages();
    }

    this.abortController.abort();
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

    if (this.inThread()) {
      const parent = this.parentMessage();
      if (parent) {
        const quote = this.listEl.createDiv({
          cls: "kit-chat__parent-quote",
        });
        quote.createEl("span", {
          text: "Parent",
          cls: "kit-chat__parent-quote-label",
        });
        quote.createEl("p", {
          text: parent.content || "(empty message)",
          cls: "kit-chat__parent-quote-text",
        });
      }
    }

    for (const message of this.activeMessages()) {
      this.renderMessageBubble(message);
    }

    this.listEl.scrollTop = this.listEl.scrollHeight;
  }

  private startElapsedTimer(): void {
    this.stopElapsedTimer();
    this.elapsedTimer = window.setInterval(() => {
      if (!this.sending) {
        this.stopElapsedTimer();
        return;
      }
      this.renderMessages();
    }, 1000);
  }

  private stopElapsedTimer(): void {
    if (this.elapsedTimer !== null) {
      window.clearInterval(this.elapsedTimer);
      this.elapsedTimer = null;
    }
  }

  private formatDuration(ms: number): string {
    if (ms < 1000) return `${ms}ms`;
    const seconds = ms / 1000;
    if (seconds < 60) {
      return seconds < 10
        ? `${seconds.toFixed(1)}s`
        : `${Math.round(seconds)}s`;
    }
    const minutes = Math.floor(seconds / 60);
    const rem = Math.round(seconds % 60);
    return `${minutes}m ${rem}s`;
  }

  private messageDurationLabel(message: ChatMessage): string | null {
    if (message.role !== "assistant") return null;
    if (typeof message.durationMs === "number") {
      return this.formatDuration(message.durationMs);
    }
    if (message.kind === "streaming" && message.startedAt) {
      return this.formatDuration(Date.now() - message.startedAt);
    }
    return null;
  }

  private finishTiming(message: ChatMessage): void {
    if (message.startedAt) {
      message.durationMs = Math.max(0, Date.now() - message.startedAt);
    }
  }

  private canReplyTo(message: ChatMessage): boolean {
    return (
      !this.inThread() &&
      !this.sending &&
      message.kind !== "streaming" &&
      (message.role === "user" || message.role === "assistant")
    );
  }

  private isMessageCollapsed(messageId: string): boolean {
    return this.collapsedMessageIds.has(messageId);
  }

  private toggleMessageCollapsed(messageId: string): void {
    if (this.editingMessageId === messageId) return;
    if (this.collapsedMessageIds.has(messageId)) {
      this.collapsedMessageIds.delete(messageId);
    } else {
      this.collapsedMessageIds.add(messageId);
    }
    this.renderMessages();
  }

  private renderMessageBubble(message: ChatMessage): void {
    if (!this.listEl) return;

    const editing = this.editingMessageId === message.id;
    const collapsed =
      !editing &&
      message.kind !== "streaming" &&
      this.isMessageCollapsed(message.id);

    const kindClass = message.kind
      ? ` kit-chat__bubble--${message.kind}`
      : "";
    const collapsedClass = collapsed ? " kit-chat__bubble--collapsed" : "";
    const bubble = this.listEl.createDiv({
      cls: `kit-chat__bubble kit-chat__bubble--${message.role}${kindClass}${collapsedClass}`,
    });

    const header = bubble.createDiv({ cls: "kit-chat__bubble-header" });

    const collapseBtn = header.createEl("button", {
      cls: "kit-chat__collapse",
      attr: {
        type: "button",
        title: collapsed ? "Expand message" : "Collapse message",
        "aria-label": collapsed ? "Expand message" : "Collapse message",
        "aria-expanded": collapsed ? "false" : "true",
      },
    });
    setIcon(collapseBtn, collapsed ? "chevron-right" : "chevron-down");
    if (editing || message.kind === "streaming") {
      collapseBtn.disabled = true;
      collapseBtn.addClass("is-disabled");
    } else {
      this.registerDomEvent(collapseBtn, "click", () => {
        this.toggleMessageCollapsed(message.id);
      });
    }

    header.createEl("span", {
      text: message.role === "user" ? "You" : "Kit",
      cls: "kit-chat__role",
    });

    if (message.mode && message.role === "user") {
      header.createEl("span", {
        text: message.mode === "edit" ? "Edit" : "Ask",
        cls: "kit-chat__mode-badge",
      });
    }

    const durationLabel = this.messageDurationLabel(message);
    if (durationLabel) {
      header.createEl("span", {
        text: durationLabel,
        cls: "kit-chat__duration",
        attr: {
          title:
            message.kind === "streaming"
              ? "Elapsed time"
              : "Time to complete",
        },
      });
    }

    if (this.canReplyTo(message)) {
      const replyBtn = header.createEl("button", {
        cls: "kit-chat__reply",
        attr: {
          type: "button",
          title: "Reply in thread",
          "aria-label": "Reply in thread",
        },
      });
      setIcon(replyBtn, "message-square");
      this.registerDomEvent(replyBtn, "click", () => {
        this.openThread(message.id);
      });
    }

    if (message.role === "user" && !this.sending && !editing) {
      const editBtn = header.createEl("button", {
        cls: "kit-chat__edit",
        attr: {
          type: "button",
          title: "Edit and resend from here",
          "aria-label": "Edit and resend from here",
        },
      });
      setIcon(editBtn, "pencil");
      this.registerDomEvent(editBtn, "click", () => {
        this.beginEditMessage(message.id);
      });
    }

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

    if (collapsed) {
      if (!this.inThread()) {
        const thread = this.threads.get(message.id);
        const replyCount = thread?.messages.length ?? 0;
        if (replyCount > 0) {
          const chip = bubble.createEl("button", {
            text: replyCount === 1 ? "1 reply" : `${replyCount} replies`,
            cls: "kit-chat__reply-chip",
            attr: {
              type: "button",
              title: "Open thread",
              "aria-label": "Open thread",
            },
          });
          chip.disabled = this.sending;
          this.registerDomEvent(chip, "click", () => {
            this.openThread(message.id);
          });
        }
      }
      return;
    }

    if (message.statusLine) {
      bubble.createEl("p", {
        text: message.statusLine,
        cls: "kit-chat__status",
      });
    }

    if (editing) {
      this.renderUserMessageEditor(bubble, message);
    } else {
      if (message.role === "user") {
        const mentions = message.mentions ?? [];
        if (mentions.length > 0) {
          const chips = bubble.createDiv({ cls: "kit-chat__message-mentions" });
          for (const doc of mentions) {
            chips.createEl("span", {
              text: `@${doc.basename}`,
              cls: "kit-chat__chip-label kit-chat__message-mention",
              attr: { title: doc.path },
            });
          }
        }
      }
      bubble.createEl("p", {
        text: message.content || (message.kind === "streaming" ? "…" : ""),
        cls: "kit-chat__content",
      });
    }

    if (!this.inThread()) {
      const thread = this.threads.get(message.id);
      const replyCount = thread?.messages.length ?? 0;
      if (replyCount > 0) {
        const chip = bubble.createEl("button", {
          text: replyCount === 1 ? "1 reply" : `${replyCount} replies`,
          cls: "kit-chat__reply-chip",
          attr: {
            type: "button",
            title: "Open thread",
            "aria-label": "Open thread",
          },
        });
        chip.disabled = this.sending;
        this.registerDomEvent(chip, "click", () => {
          this.openThread(message.id);
        });
      }
    }

    if (
      message.kind === "proposal" &&
      message.role === "assistant" &&
      !this.sending
    ) {
      const actions = bubble.createDiv({ cls: "kit-chat__proposal-actions" });
      const applyBtn = actions.createEl("button", {
        text: "Apply",
        cls: "mod-cta kit-chat__apply",
        attr: { type: "button" },
      });
      actions.createEl("span", {
        text: "Or send another Edit message to revise.",
        cls: "kit-chat__proposal-hint",
      });
      this.registerDomEvent(applyBtn, "click", () => {
        void this.handleApply(message.id);
      });
    }
  }

  private renderUserMessageEditor(
    bubble: HTMLElement,
    message: ChatMessage,
  ): void {
    const editor = bubble.createDiv({ cls: "kit-chat__message-editor" });

    if (this.editingMentions.length > 0) {
      const chips = editor.createDiv({ cls: "kit-chat__message-edit-mentions" });
      for (const doc of this.editingMentions) {
        const chip = chips.createDiv({ cls: "kit-chat__chip" });
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
          this.editingMentions = this.editingMentions.filter(
            (m) => m.path !== doc.path,
          );
          this.renderMessages();
        });
      }
    }

    const textarea = editor.createEl("textarea", {
      cls: "kit-chat__message-edit-input",
      attr: { rows: "4", "aria-label": "Edit message" },
    });
    textarea.value = message.content;

    const actions = editor.createDiv({ cls: "kit-chat__message-edit-actions" });
    const cancelBtn = actions.createEl("button", {
      text: "Cancel",
      cls: "kit-chat__message-edit-cancel",
      attr: { type: "button" },
    });
    const resendBtn = actions.createEl("button", {
      text: "Save & resend",
      cls: "mod-cta kit-chat__message-edit-resend",
      attr: { type: "button" },
    });

    window.setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(textarea.value.length, textarea.value.length);
    }, 0);

    this.registerDomEvent(cancelBtn, "click", () => {
      this.editingMessageId = null;
      this.editingMentions = [];
      this.renderMessages();
    });

    this.registerDomEvent(resendBtn, "click", () => {
      void this.resendFromEditedMessage(message.id, textarea.value);
    });

    this.registerDomEvent(textarea, "keydown", (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        this.editingMessageId = null;
        this.editingMentions = [];
        this.renderMessages();
        return;
      }
      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        void this.resendFromEditedMessage(message.id, textarea.value);
      }
    });
  }

  /**
   * Split legacy "@path @path\\nbody" content into mentions + body when
   * mentions were not stored on the message yet.
   */
  private mentionsAndBodyFromMessage(message: ChatMessage): {
    mentions: ChatDocumentRef[];
    body: string;
  } {
    if (message.mentions && message.mentions.length > 0) {
      return { mentions: [...message.mentions], body: message.content };
    }

    const lines = message.content.split("\n");
    const first = lines[0] ?? "";
    if (!first.includes("@")) {
      return { mentions: [], body: message.content };
    }

    const tokens = first.trim().split(/\s+/);
    if (tokens.length === 0 || !tokens.every((t) => t.startsWith("@"))) {
      return { mentions: [], body: message.content };
    }

    const mentions: ChatDocumentRef[] = tokens.map((token) => {
      const path = token.slice(1);
      const basename = path.includes("/")
        ? (path.split("/").pop() ?? path)
        : path;
      return { path, basename: basename.replace(/\.md$/i, "") };
    });

    const body = lines.slice(1).join("\n").replace(/^\n/, "");
    return { mentions, body };
  }

  private beginEditMessage(messageId: string): void {
    if (this.sending) return;
    const message = this.activeMessages().find((m) => m.id === messageId);
    if (!message || message.role !== "user") return;

    const parsed = this.mentionsAndBodyFromMessage(message);
    message.content = parsed.body;
    message.mentions = parsed.mentions;
    this.editingMentions = [...parsed.mentions];
    this.editingMessageId = messageId;
    this.collapsedMessageIds.delete(messageId);
    this.renderMessages();
  }

  private async resendFromEditedMessage(
    messageId: string,
    rawText: string,
  ): Promise<void> {
    const text = rawText.trim();
    if (!text) {
      new Notice("Message can’t be empty.");
      return;
    }

    const messages = this.activeMessages();
    const index = messages.findIndex((m) => m.id === messageId);
    if (index < 0) return;

    const userMessage = messages[index];
    if (!userMessage || userMessage.role !== "user") return;

    if (!this.inThread() && this.threads.has(messageId)) {
      new Notice(
        "This message has a thread — replies were kept, but the thread may be stale.",
      );
    }

    const mentions = [...this.editingMentions];
    this.replaceActiveMessages(messages.slice(0, index + 1));
    userMessage.content = text;
    userMessage.mentions = mentions;
    this.editingMessageId = null;
    this.editingMentions = [];
    this.setActiveCodexThreadId(null);

    const mode = userMessage.mode ?? this.mode;
    this.mode = mode;
    this.syncModeButtons();

    await this.runAssistantTurn({
      mode,
      userText: text,
      userMessage,
      mentions,
    });
  }

  private applyStreamEvent(
    message: ChatMessage,
    event: CodexStreamEvent,
  ): void {
    if (event.type === "thread.started") {
      this.setActiveCodexThreadId(event.threadId);
      return;
    }
    if (event.type === "status" || event.type === "turn.started") {
      message.statusLine =
        event.type === "status" ? event.message : "Working…";
      this.renderMessages();
      return;
    }
    if (event.type === "agent_text") {
      message.content = event.replace
        ? event.text
        : `${message.content}${event.text}`;
      this.renderMessages();
      return;
    }
    if (event.type === "turn.failed" || event.type === "error") {
      message.statusLine = event.message;
      this.renderMessages();
    }
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

  private isAbortError(error: unknown): boolean {
    return (
      (error instanceof DOMException && error.name === "AbortError") ||
      (error instanceof Error && error.name === "AbortError")
    );
  }

  private async handleSend(): Promise<void> {
    if (!this.inputEl || this.sending) return;
    if (this.codexReady !== true) {
      new Notice("Codex CLI is not available. Check Kit settings.");
      return;
    }

    const vaultPath = this.vaultPath();
    if (!vaultPath) {
      new Notice("Could not resolve vault path.");
      return;
    }

    const text = this.inputEl.value.trim();
    if (!text) return;

    this.editingMessageId = null;
    this.editingMentions = [];
    this.inputEl.value = "";

    const mentions = [...this.mentions];
    const userMessage = createChatMessage("user", text, {
      mode: this.mode,
      mentions,
    });
    this.activeMessages().push(userMessage);
    this.touchActiveThread();

    await this.runAssistantTurn({
      mode: this.mode,
      userText: text,
      userMessage,
      mentions,
      vaultPath,
    });
  }

  private async runAssistantTurn(options: {
    mode: ChatMode;
    userText: string;
    userMessage: ChatMessage;
    mentions: ChatDocumentRef[];
    vaultPath?: string;
  }): Promise<void> {
    if (this.sending) return;
    if (this.codexReady !== true) {
      new Notice("Codex CLI is not available. Check Kit settings.");
      return;
    }

    const vaultPath = options.vaultPath ?? this.vaultPath();
    if (!vaultPath) {
      new Notice("Could not resolve vault path.");
      return;
    }

    this.sending = true;
    this.abortController = new AbortController();
    this.updateActionButtons();

    const startedAt = Date.now();
    const streaming = createChatMessage("assistant", "", {
      kind: "streaming",
      statusLine: "Starting Codex…",
      mode: options.mode,
      startedAt,
    });
    this.activeMessages().push(streaming);
    this.touchActiveThread();
    this.renderMessages();
    this.startElapsedTimer();

    const activeTab = this.plugin.activeTabService.getContext();
    const laneMessages = this.activeMessages();

    try {
      const result = await this.plugin.chatService.startTurn({
        mode: options.mode,
        userText: options.userText,
        history: laneMessages.filter(
          (m) =>
            m.id !== streaming.id && m.id !== options.userMessage.id,
        ),
        activeTab,
        mentions: options.mentions,
        threadId: this.getActiveCodexThreadId(),
        vaultPath,
        binary: this.plugin.settings.codexBinary,
        signal: this.abortController.signal,
        threadContext: this.buildThreadContext(),
        onEvent: (event) => this.applyStreamEvent(streaming, event),
      });

      if (result.threadId) {
        this.setActiveCodexThreadId(result.threadId);
      }
      streaming.content = result.finalText;
      streaming.kind = result.kind;
      streaming.statusLine = undefined;
      this.finishTiming(streaming);
      this.touchActiveThread();
      this.renderMessages();
    } catch (error) {
      this.finishTiming(streaming);
      if (this.isAbortError(error)) {
        streaming.content = streaming.content || "Stopped.";
        streaming.kind = "error";
        streaming.statusLine = "Stopped";
      } else {
        const message =
          error instanceof Error ? error.message : String(error);
        streaming.content = message;
        streaming.kind = "error";
        streaming.statusLine = "Error";
        new Notice("Kit chat failed — see the message in chat.");
      }
      this.touchActiveThread();
      this.renderMessages();
    } finally {
      this.stopElapsedTimer();
      this.sending = false;
      this.abortController = null;
      this.updateActionButtons();
      this.renderMessages();
      this.inputEl?.focus();
    }
  }

  private async handleApply(proposalMessageId: string): Promise<void> {
    if (this.sending) return;
    if (this.codexReady !== true) {
      new Notice("Codex CLI is not available. Check Kit settings.");
      return;
    }

    const codexThreadId = this.getActiveCodexThreadId();
    if (!codexThreadId) {
      new Notice("No Codex session to apply. Send an Edit plan first.");
      return;
    }

    const vaultPath = this.vaultPath();
    if (!vaultPath) {
      new Notice("Could not resolve vault path.");
      return;
    }

    const laneMessages = this.activeMessages();
    const proposal = laneMessages.find((m) => m.id === proposalMessageId);
    if (!proposal || proposal.kind !== "proposal") return;

    const lastProposal = [...laneMessages]
      .reverse()
      .find((m) => m.kind === "proposal");
    if (!lastProposal || lastProposal.id !== proposalMessageId) {
      new Notice("Only the latest plan can be applied.");
      return;
    }

    this.sending = true;
    this.abortController = new AbortController();
    this.updateActionButtons();
    this.renderMessages();

    const startedAt = Date.now();
    const streaming = createChatMessage("assistant", "", {
      kind: "streaming",
      statusLine: "Applying plan…",
      mode: "edit",
      startedAt,
    });
    laneMessages.push(streaming);
    this.touchActiveThread();
    this.renderMessages();
    this.startElapsedTimer();

    try {
      const result = await this.plugin.chatService.applyPlan({
        threadId: codexThreadId,
        vaultPath,
        binary: this.plugin.settings.codexBinary,
        signal: this.abortController.signal,
        onEvent: (event) => this.applyStreamEvent(streaming, event),
      });

      if (result.threadId) {
        this.setActiveCodexThreadId(result.threadId);
      }
      streaming.content = result.finalText;
      streaming.kind = "applied";
      streaming.statusLine = undefined;
      this.finishTiming(streaming);
      proposal.kind = "normal";
      this.touchActiveThread();
      this.renderMessages();
      new Notice("Plan applied — check your vault notes.");
    } catch (error) {
      this.finishTiming(streaming);
      if (this.isAbortError(error)) {
        streaming.content = streaming.content || "Apply stopped.";
        streaming.kind = "error";
        streaming.statusLine = "Stopped";
      } else {
        const message =
          error instanceof Error ? error.message : String(error);
        streaming.content = message;
        streaming.kind = "error";
        streaming.statusLine = "Error";
        new Notice("Apply failed — see the message in chat.");
      }
      this.touchActiveThread();
      this.renderMessages();
    } finally {
      this.stopElapsedTimer();
      this.sending = false;
      this.abortController = null;
      this.updateActionButtons();
      this.renderMessages();
      this.inputEl?.focus();
    }
  }
}
