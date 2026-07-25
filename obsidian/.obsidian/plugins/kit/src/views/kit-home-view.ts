import { ItemView, WorkspaceLeaf } from "obsidian";
import { VIEW_TYPE_KIT } from "../constants";
import type KitPlugin from "../main";
import { HERO_LOGO_SVG, KIT_LOGO_ICON_ID } from "../utils/icons";

export class KitHomeView extends ItemView {
  plugin: KitPlugin;

  constructor(leaf: WorkspaceLeaf, plugin: KitPlugin) {
    super(leaf);
    this.plugin = plugin;
  }

  getViewType(): string {
    return VIEW_TYPE_KIT;
  }

  getDisplayText(): string {
    return "Kit";
  }

  getIcon(): string {
    return KIT_LOGO_ICON_ID;
  }

  async onOpen(): Promise<void> {
    this.render();
    if (this.plugin.settings.showHelloOnOpen) {
      this.plugin.helloService.greet();
    }
  }

  async onClose(): Promise<void> {
    this.contentEl.empty();
  }

  private render(): void {
    const root = this.contentEl;
    root.empty();
    root.addClass("kit-home");

    const header = root.createDiv({ cls: "kit-home__header" });
    header.innerHTML = HERO_LOGO_SVG;

    root.createEl("h1", {
      text: "Kit",
      cls: "kit-home__headline",
    });

    root.createEl("p", {
      text: "Personal leadership toolkit.",
      cls: "kit-home__tagline",
    });

    const actions = root.createDiv({ cls: "kit-home__actions" });
    const helloBtn = actions.createEl("button", {
      text: "Say hello",
      cls: "mod-cta",
      attr: { type: "button" },
    });
    this.registerDomEvent(helloBtn, "click", () => {
      this.plugin.helloService.greet();
    });
  }
}
