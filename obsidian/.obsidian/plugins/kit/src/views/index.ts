import { VIEW_TYPE_KIT } from "../constants";
import type KitPlugin from "../main";
import { KitHomeView } from "./kit-home-view";

export function registerViews(plugin: KitPlugin): void {
  plugin.registerView(
    VIEW_TYPE_KIT,
    (leaf) => new KitHomeView(leaf, plugin),
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
