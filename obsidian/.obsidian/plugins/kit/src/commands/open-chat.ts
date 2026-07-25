import type KitPlugin from "../main";
import { activateKitChat } from "../views";

export function registerOpenChatCommand(plugin: KitPlugin): void {
  plugin.addCommand({
    id: "open-kit-chat",
    name: "Open Kit chat",
    callback: () => {
      void activateKitChat(plugin);
    },
  });
}
