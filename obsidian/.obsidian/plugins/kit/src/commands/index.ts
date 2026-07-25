import type KitPlugin from "../main";
import { registerHelloCommand } from "./hello";
import { registerOpenKitCommand } from "./open-kit";

export function registerCommands(plugin: KitPlugin): void {
  registerOpenKitCommand(plugin);
  registerHelloCommand(plugin);
}
