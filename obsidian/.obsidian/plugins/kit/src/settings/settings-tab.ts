import { App, PluginSettingTab, Setting } from "obsidian";
import type KitPlugin from "../main";

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
  }
}
