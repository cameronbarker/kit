import { VIEW_TYPE_KIT, VIEW_TYPE_KIT_CHAT } from "../constants";
import type KitPlugin from "../main";
import { KitChatView } from "./kit-chat-view";
import { KitHomeView } from "./kit-home-view";

export function registerViews(plugin: KitPlugin): void {
  plugin.registerView(
    VIEW_TYPE_KIT,
    (leaf) => new KitHomeView(leaf, plugin),
  );
  plugin.registerView(
    VIEW_TYPE_KIT_CHAT,
    (leaf) => new KitChatView(leaf, plugin),
  );
}

export async function activateKit(plugin: KitPlugin): Promise<void> {
  const { workspace } = plugin.app;
  const leaves = workspace.getLeavesOfType(VIEW_TYPE_KIT);

  let leaf =
    leaves.find((candidate) => candidate.getRoot() === workspace.rootSplit) ??
    null;

  if (!leaf) {
    for (const extra of leaves) {
      extra.detach();
    }
    leaf = workspace.getLeaf("tab");
    await leaf.setViewState({
      type: VIEW_TYPE_KIT,
      active: true,
    });
  }

  workspace.revealLeaf(leaf);
}

export async function activateKitChat(plugin: KitPlugin): Promise<void> {
  const { workspace } = plugin.app;
  const leaves = workspace.getLeavesOfType(VIEW_TYPE_KIT_CHAT);

  if (leaves.length > 0) {
    workspace.revealLeaf(leaves[0]!);
    return;
  }

  const leaf = workspace.getRightLeaf(false);
  if (!leaf) return;

  await leaf.setViewState({
    type: VIEW_TYPE_KIT_CHAT,
    active: true,
  });
  workspace.revealLeaf(leaf);
}
