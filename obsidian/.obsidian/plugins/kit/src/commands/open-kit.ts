import type KitPlugin from "../main";
import { activateKit } from "../views";

export function registerOpenKitCommand(plugin: KitPlugin): void {
  plugin.addCommand({
    id: "open-kit",
    name: "Open Kit",
    callback: () => {
      void activateKit(plugin);
    },
  });
}
