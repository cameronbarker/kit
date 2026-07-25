import { App, FileView, WorkspaceLeaf } from "obsidian";
import type { ActiveTabContext } from "../types";

function isMainLeaf(app: App, leaf: WorkspaceLeaf): boolean {
  return leaf.getRoot() === app.workspace.rootSplit;
}

/**
 * Tracks the main-area tab (root split), ignoring sidebar focus.
 */
export class ActiveTabService {
  private lastMainLeaf: WorkspaceLeaf | null = null;

  constructor(private readonly app: App) {}

  /** Call when the active leaf changes so we remember the last main tab. */
  onActiveLeafChange(leaf: WorkspaceLeaf | null): void {
    if (leaf && isMainLeaf(this.app, leaf)) {
      this.lastMainLeaf = leaf;
    }
  }

  getContext(): ActiveTabContext | null {
    const leaf = this.resolveMainLeaf();
    if (!leaf?.view) return null;

    const { view } = leaf;
    const file = view instanceof FileView ? view.file : null;

    return {
      viewType: view.getViewType(),
      title: file?.basename ?? view.getDisplayText(),
      filePath: file?.path ?? null,
    };
  }

  private resolveMainLeaf(): WorkspaceLeaf | null {
    const { workspace } = this.app;
    const active = workspace.activeLeaf;

    if (active && isMainLeaf(this.app, active)) {
      this.lastMainLeaf = active;
      return active;
    }

    if (this.lastMainLeaf?.view) {
      return this.lastMainLeaf;
    }

    const recent = workspace.getMostRecentLeaf(workspace.rootSplit);
    if (recent && isMainLeaf(this.app, recent)) {
      this.lastMainLeaf = recent;
      return recent;
    }

    return null;
  }
}
