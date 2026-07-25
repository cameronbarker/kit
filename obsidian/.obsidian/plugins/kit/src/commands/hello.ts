import type KitPlugin from "../main";

export function registerHelloCommand(plugin: KitPlugin): void {
  plugin.addCommand({
    id: "hello-from-kit",
    name: "Hello from Kit",
    callback: () => {
      plugin.helloService.greet();
    },
  });
}
