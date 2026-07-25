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
} from "../types";
import { DocumentMentionModal } from "../ui/document-mention-modal";

export class KitChatView extends ItemView {
  plugin: KitPlugin;
  private messages: ChatMessage[] = [];
  private mentions: ChatDocumentRef[] = [];
  private mode: ChatMode = "ask";
  private threadId: string | null = null;
  private listEl: HTMLElement | null = null;
  private contextEl: HTMLElement | null = null;
  private mentionsEl: HTMLElement | null = null;
  private inputEl: HTMLTextAreaElement | null = null;
  private modeAskBtn: HTMLButtonElement | null = null;
  private modeEditBtn: HTMLButtonElement | null = null;
  private sendBtn: HTMLButtonElement | null = null;
  private cancelBtn: HTMLButtonElement | null = null;
  private sending = false;
  private mentionModalOpen = false;
  private abortController: AbortController | null = null;
  private codexReady: boolean | null = null;
  private codexStatusEl: HTMLElement | null = null;
  private elapsedTimer: number | null = null;

  constructor(leaf: WorkspaceLeaf, plugin: KitPlugin) {
    super(leaf);
    this.plugin = plugin;
    this.mode = plugin.settings.defaultChatMode;
    this.messages = [
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
        this.updateContextLabel();
      }),
    );
    this.registerEvent(
      this.app.workspace.on("file-open", () => {
        this.updateContextLabel();
      }),
    );
    void this.refreshCodexStatus();
  }

  async onClose(): Promise<void> {
    this.stopElapsedTimer();
    this.abortController?.abort();
    this.contentEl.empty();
    this.listEl = null;
    this.contextEl = null;
    this.mentionsEl = null;
    this.inputEl = null;
    this.modeAskBtn = null;
    this.modeEditBtn = null;
    this.sendBtn = null;
    this.cancelBtn = null;
    this.codexStatusEl = null;
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
      this.updateCodexStatusLabel(
        "Codex chat requires the Obsidian desktop app.",
      );
      this.updateActionButtons();
      return;
    }

    const result = await checkCodexBinary(this.plugin.settings.codexBinary);
    this.codexReady = result.ok;
    if (result.ok) {
      const bits = ["Codex ready"];
      if (result.version) bits.push(result.version);
      this.updateCodexStatusLabel(bits.join(" · "));
    } else {
      this.updateCodexStatusLabel(
        `Codex not found. Install the CLI or set Kit settings → Codex binary to /usr/local/bin/codex. ${result.error ?? ""}`.trim(),
      );
    }
    this.updateActionButtons();
  }

  private updateCodexStatusLabel(text: string): void {
    if (!this.codexStatusEl) return;
    this.codexStatusEl.setText(text);
  }

  private render(): void {
    const root = this.contentEl;
    root.empty();
    root.addClass("kit-chat");

    if (!Platform.isDesktopApp) {
      root.createEl("h2", { text: "Kit chat", cls: "kit-chat__title" });
      root.createEl("p", {
        text: "Codex chat requires the Obsidian desktop app.",
        cls: "kit-chat__subtitle",
      });
      return;
    }

    root.createEl("h2", { text: "Kit chat", cls: "kit-chat__title" });
    root.createEl("p", {
      text: "Ask answers read-only. Edit plans changes — Apply writes them.",
      cls: "kit-chat__subtitle",
    });

    this.codexStatusEl = root.createDiv({ cls: "kit-chat__codex-status" });
    this.updateCodexStatusLabel("Checking Codex…");

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
      text: "Cancel",
      cls: "kit-chat__cancel",
      attr: { type: "button" },
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
      this.abortController?.abort();
    });
    this.registerDomEvent(this.sendBtn, "click", () => {
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

    this.updateActionButtons();
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
    }
    if (this.cancelBtn) {
      this.cancelBtn.toggleClass("is-visible", this.sending);
      this.cancelBtn.disabled = !this.sending;
    }
    if (this.modeAskBtn) this.modeAskBtn.disabled = this.sending;
    if (this.modeEditBtn) this.modeEditBtn.disabled = this.sending;
    if (this.inputEl) this.inputEl.disabled = this.sending;
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

  private renderMessageBubble(message: ChatMessage): void {
    if (!this.listEl) return;

    const kindClass = message.kind
      ? ` kit-chat__bubble--${message.kind}`
      : "";
    const bubble = this.listEl.createDiv({
      cls: `kit-chat__bubble kit-chat__bubble--${message.role}${kindClass}`,
    });

    const header = bubble.createDiv({ cls: "kit-chat__bubble-header" });
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

    if (message.statusLine) {
      bubble.createEl("p", {
        text: message.statusLine,
        cls: "kit-chat__status",
      });
    }

    bubble.createEl("p", {
      text: message.content || (message.kind === "streaming" ? "…" : ""),
      cls: "kit-chat__content",
    });

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

  private applyStreamEvent(
    message: ChatMessage,
    event: CodexStreamEvent,
  ): void {
    if (event.type === "thread.started") {
      this.threadId = event.threadId;
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

    this.sending = true;
    this.abortController = new AbortController();
    this.updateActionButtons();
    this.inputEl.value = "";

    const mentionPrefix =
      this.mentions.length > 0
        ? `${this.mentions.map((doc) => `@${doc.path}`).join(" ")}\n`
        : "";
    const userMessage = createChatMessage(
      "user",
      `${mentionPrefix}${text}`,
      { mode: this.mode },
    );
    this.messages.push(userMessage);

    const startedAt = Date.now();
    const streaming = createChatMessage("assistant", "", {
      kind: "streaming",
      statusLine: "Starting Codex…",
      mode: this.mode,
      startedAt,
    });
    this.messages.push(streaming);
    this.renderMessages();
    this.startElapsedTimer();

    const activeTab = this.plugin.activeTabService.getContext();
    const mentions = [...this.mentions];

    try {
      const result = await this.plugin.chatService.startTurn({
        mode: this.mode,
        userText: text,
        history: this.messages.filter(
          (m) => m.id !== streaming.id && m.id !== userMessage.id,
        ),
        activeTab,
        mentions,
        threadId: this.threadId,
        vaultPath,
        binary: this.plugin.settings.codexBinary,
        signal: this.abortController.signal,
        onEvent: (event) => this.applyStreamEvent(streaming, event),
      });

      if (result.threadId) {
        this.threadId = result.threadId;
      }
      streaming.content = result.finalText;
      streaming.kind = result.kind;
      streaming.statusLine = undefined;
      this.finishTiming(streaming);
      this.renderMessages();
    } catch (error) {
      this.finishTiming(streaming);
      if (this.isAbortError(error)) {
        streaming.content = streaming.content || "Cancelled.";
        streaming.kind = "error";
        streaming.statusLine = "Cancelled";
      } else {
        const message =
          error instanceof Error ? error.message : String(error);
        streaming.content = message;
        streaming.kind = "error";
        streaming.statusLine = "Error";
        new Notice("Kit chat failed — see the message in chat.");
      }
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
    if (!this.threadId) {
      new Notice("No Codex session to apply. Send an Edit plan first.");
      return;
    }

    const vaultPath = this.vaultPath();
    if (!vaultPath) {
      new Notice("Could not resolve vault path.");
      return;
    }

    const proposal = this.messages.find((m) => m.id === proposalMessageId);
    if (!proposal || proposal.kind !== "proposal") return;

    // Only allow Apply on the latest proposal.
    const lastProposal = [...this.messages]
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
    this.messages.push(streaming);
    this.renderMessages();
    this.startElapsedTimer();

    try {
      const result = await this.plugin.chatService.applyPlan({
        threadId: this.threadId,
        vaultPath,
        binary: this.plugin.settings.codexBinary,
        signal: this.abortController.signal,
        onEvent: (event) => this.applyStreamEvent(streaming, event),
      });

      if (result.threadId) {
        this.threadId = result.threadId;
      }
      streaming.content = result.finalText;
      streaming.kind = "applied";
      streaming.statusLine = undefined;
      this.finishTiming(streaming);
      proposal.kind = "normal";
      this.renderMessages();
      new Notice("Plan applied — check your vault notes.");
    } catch (error) {
      this.finishTiming(streaming);
      if (this.isAbortError(error)) {
        streaming.content = streaming.content || "Apply cancelled.";
        streaming.kind = "error";
        streaming.statusLine = "Cancelled";
      } else {
        const message =
          error instanceof Error ? error.message : String(error);
        streaming.content = message;
        streaming.kind = "error";
        streaming.statusLine = "Error";
        new Notice("Apply failed — see the message in chat.");
      }
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
