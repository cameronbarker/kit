import { Plugin } from "obsidian";
import { registerCommands } from "./commands";
import { DEFAULT_SETTINGS, type KitSettings } from "./settings/settings";
import { KitSettingTab } from "./settings/settings-tab";
import { ActiveTabService } from "./services/active-tab-service";
import { ApplyCheckpointService } from "./services/apply-checkpoint-service";
import { ChatHistoryService } from "./services/chat-history-service";
import { ChatService } from "./services/chat-service";
import { HelloService } from "./services/hello-service";
import { KIT_LOGO_ICON_ID, registerKitIcons } from "./utils/icons";
import { activateKit, activateKitChat, registerViews } from "./views";

export default class KitPlugin extends Plugin {
  settings!: KitSettings;
  helloService!: HelloService;
  chatService!: ChatService;
  chatHistoryService!: ChatHistoryService;
  applyCheckpointService!: ApplyCheckpointService;
  activeTabService!: ActiveTabService;

  async onload(): Promise<void> {
    await this.loadSettings();

    this.helloService = new HelloService();
    this.chatService = new ChatService();
    this.chatHistoryService = new ChatHistoryService(this.app);
    this.applyCheckpointService = new ApplyCheckpointService(this.app);
    this.activeTabService = new ActiveTabService(this.app);

    this.registerEvent(
      this.app.workspace.on("active-leaf-change", (leaf) => {
        this.activeTabService.onActiveLeafChange(leaf);
      }),
    );

    registerKitIcons();
    registerViews(this);
    registerCommands(this);

    this.addRibbonIcon(KIT_LOGO_ICON_ID, "Open Kit", () => {
      void activateKit(this);
    });

    this.addRibbonIcon("message-square", "Open Kit chat", () => {
      void activateKitChat(this);
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
