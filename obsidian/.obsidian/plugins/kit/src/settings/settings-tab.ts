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
  }
}
