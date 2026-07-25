import type KitPlugin from "../main";
import { registerHelloCommand } from "./hello";
import { registerOpenChatCommand } from "./open-chat";
import { registerOpenKitCommand } from "./open-kit";

export function registerCommands(plugin: KitPlugin): void {
  registerOpenKitCommand(plugin);
  registerOpenChatCommand(plugin);
  registerHelloCommand(plugin);
}
