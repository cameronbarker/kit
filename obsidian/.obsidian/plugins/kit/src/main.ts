import { Plugin } from "obsidian";
import { registerCommands } from "./commands";
import { DEFAULT_SETTINGS, type KitSettings } from "./settings/settings";
import { KitSettingTab } from "./settings/settings-tab";
import { HelloService } from "./services/hello-service";
import { KIT_LOGO_ICON_ID, registerKitIcons } from "./utils/icons";
import { activateKit, registerViews } from "./views";

export default class KitPlugin extends Plugin {
  settings!: KitSettings;
  helloService!: HelloService;

  async onload(): Promise<void> {
    await this.loadSettings();

    this.helloService = new HelloService();
    registerKitIcons();
    registerViews(this);
    registerCommands(this);

    this.addRibbonIcon(KIT_LOGO_ICON_ID, "Open Kit", () => {
      void activateKit(this);
    });

    this.addSettingTab(new KitSettingTab(this.app, this));
  }

  async onunload(): Promise<void> {}

  async loadSettings(): Promise<void> {
    this.settings = Object.assign(
      {},
      DEFAULT_SETTINGS,
      (await this.loadData()) as Partial<KitSettings>,
    );
  }

  async saveSettings(): Promise<void> {
    await this.saveData(this.settings);
  }
}
