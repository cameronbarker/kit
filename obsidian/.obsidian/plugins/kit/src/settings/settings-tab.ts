import { App, PluginSettingTab, Setting } from "obsidian";
import type KitPlugin from "../main";
import type { ChatMode } from "../types";

export class KitSettingTab extends PluginSettingTab {
  plugin: KitPlugin;

  constructor(app: App, plugin: KitPlugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display(): void {
    const { containerEl } = this;
    containerEl.empty();

    new Setting(containerEl)
      .setName("Show hello on open")
      .setDesc("Show a hello notice when Kit home opens.")
      .addToggle((toggle) =>
        toggle
          .setValue(this.plugin.settings.showHelloOnOpen)
          .onChange(async (value) => {
            this.plugin.settings.showHelloOnOpen = value;
            await this.plugin.saveSettings();
          }),
      );

    new Setting(containerEl)
      .setName("Codex binary")
      .setDesc(
        "Absolute path to the Codex CLI (recommended). Leave blank to auto-detect common locations like /usr/local/bin/codex. Obsidian often cannot see your shell PATH.",
      )
      .addText((text) =>
        text
          .setPlaceholder("codex")
          .setValue(this.plugin.settings.codexBinary)
          .onChange(async (value) => {
            this.plugin.settings.codexBinary = value.trim();
            await this.plugin.saveSettings();
          }),
      );

    new Setting(containerEl)
      .setName("Default chat mode")
      .setDesc("Ask is read-only. Edit plans changes, then Apply writes them.")
      .addDropdown((dropdown) =>
        dropdown
          .addOption("ask", "Ask")
          .addOption("edit", "Edit")
          .setValue(this.plugin.settings.defaultChatMode)
          .onChange(async (value) => {
            this.plugin.settings.defaultChatMode = value as ChatMode;
            await this.plugin.saveSettings();
          }),
      );

    new Setting(containerEl)
      .setName("Chat retrieval (qmd)")
      .setDesc(
        "Before each Ask/Edit turn, search the local qmd index and pass related notes into Codex.",
      )
      .addToggle((toggle) =>
        toggle
          .setValue(this.plugin.settings.chatRetrievalEnabled)
          .onChange(async (value) => {
            this.plugin.settings.chatRetrievalEnabled = value;
            await this.plugin.saveSettings();
          }),
      );

    new Setting(containerEl)
      .setName("qmd binary")
      .setDesc(
        "Absolute path to qmd (recommended). Leave blank to auto-detect. Obsidian often cannot see your shell PATH.",
      )
      .addText((text) =>
        text
          .setPlaceholder("qmd")
          .setValue(this.plugin.settings.qmdBinary)
          .onChange(async (value) => {
            this.plugin.settings.qmdBinary = value.trim();
            await this.plugin.saveSettings();
          }),
      );

    new Setting(containerEl)
      .setName("qmd index")
      .setDesc("Index name passed to qmd --index (default: kit).")
      .addText((text) =>
        text
          .setPlaceholder("kit")
          .setValue(this.plugin.settings.qmdIndex)
          .onChange(async (value) => {
            this.plugin.settings.qmdIndex = value.trim() || "kit";
            await this.plugin.saveSettings();
          }),
      );

    new Setting(containerEl)
      .setName("Retrieval hit limit")
      .setDesc("Maximum qmd hits to inject into each chat turn.")
      .addText((text) =>
        text
          .setPlaceholder("5")
          .setValue(String(this.plugin.settings.chatRetrievalLimit))
          .onChange(async (value) => {
            const parsed = Number.parseInt(value.trim(), 10);
            this.plugin.settings.chatRetrievalLimit =
              Number.isFinite(parsed) && parsed > 0 ? parsed : 5;
            await this.plugin.saveSettings();
          }),
      );
  }
}
