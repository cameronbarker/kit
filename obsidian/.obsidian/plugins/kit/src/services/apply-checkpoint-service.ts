import { App, normalizePath } from "obsidian";
import { CHAT_HISTORY_FOLDER } from "./chat-history-service";

const ELIGIBLE_EXTENSIONS = new Set([
  "md",
  "txt",
  "canvas",
  "csv",
  "json",
]);

const MAX_SNAPSHOT_BYTES = Math.floor(1.5 * 1024 * 1024);

export type CheckpointChangeOp = "create" | "modify" | "delete";

export interface CheckpointChange {
  path: string;
  op: CheckpointChangeOp;
  /** True when we have no before-copy to restore (binary/oversized/skipped). */
  unrestorable?: boolean;
}

export interface ApplyCheckpointManifest {
  id: string;
  createdAt: number;
  applyMessageId: string;
  changes: CheckpointChange[];
}

interface InventoryEntry {
  path: string;
  mtime: number;
  size: number;
  eligible: boolean;
  snapshotted: boolean;
}

interface InventoryFile {
  checkpointId: string;
  conversationId: string;
  createdAt: number;
  entries: InventoryEntry[];
}

function extensionOf(path: string): string {
  const base = path.split("/").pop() ?? path;
  const dot = base.lastIndexOf(".");
  if (dot <= 0) return "";
  return base.slice(dot + 1).toLowerCase();
}

function shouldSkipPath(path: string): boolean {
  const normalized = normalizePath(path);
  if (normalized === ".obsidian" || normalized.startsWith(".obsidian/")) {
    return true;
  }
  if (
    normalized === CHAT_HISTORY_FOLDER ||
    normalized.startsWith(`${CHAT_HISTORY_FOLDER}/`)
  ) {
    return true;
  }
  return false;
}

function isEligiblePath(path: string): boolean {
  return ELIGIBLE_EXTENSIONS.has(extensionOf(path));
}

export class ApplyCheckpointService {
  constructor(private readonly app: App) {}

  checkpointRoot(conversationId: string, checkpointId: string): string {
    return normalizePath(
      `${CHAT_HISTORY_FOLDER}/${conversationId}/checkpoints/${checkpointId}`,
    );
  }

  conversationDir(conversationId: string): string {
    return normalizePath(`${CHAT_HISTORY_FOLDER}/${conversationId}`);
  }

  async begin(conversationId: string): Promise<{ checkpointId: string }> {
    const checkpointId = `ckpt-${Date.now()}`;
    const root = this.checkpointRoot(conversationId, checkpointId);
    const beforeRoot = normalizePath(`${root}/before`);
    await this.ensureDir(root);
    await this.ensureDir(beforeRoot);

    const entries: InventoryEntry[] = [];
    const paths = await this.listVaultFiles();

    for (const path of paths) {
      if (shouldSkipPath(path)) continue;
      const stat = await this.app.vault.adapter.stat(path);
      if (!stat || stat.type !== "file") continue;

      const eligible = isEligiblePath(path);
      let snapshotted = false;
      if (eligible && stat.size <= MAX_SNAPSHOT_BYTES) {
        const data = await this.app.vault.adapter.readBinary(path);
        const dest = normalizePath(`${beforeRoot}/${path}`);
        await this.ensureParentDir(dest);
        await this.app.vault.adapter.writeBinary(dest, data);
        snapshotted = true;
      }

      entries.push({
        path,
        mtime: stat.mtime,
        size: stat.size,
        eligible,
        snapshotted,
      });
    }

    const inventory: InventoryFile = {
      checkpointId,
      conversationId,
      createdAt: Date.now(),
      entries,
    };
    await this.app.vault.adapter.write(
      normalizePath(`${root}/inventory.json`),
      `${JSON.stringify(inventory, null, 2)}\n`,
    );

    return { checkpointId };
  }

  async finalize(
    conversationId: string,
    checkpointId: string,
    applyMessageId: string,
  ): Promise<ApplyCheckpointManifest> {
    const root = this.checkpointRoot(conversationId, checkpointId);
    const inventoryPath = normalizePath(`${root}/inventory.json`);
    const raw = await this.app.vault.adapter.read(inventoryPath);
    const inventory = JSON.parse(raw) as InventoryFile;
    const before = new Map(
      inventory.entries.map((entry) => [entry.path, entry]),
    );

    const afterEntries = new Map<string, InventoryEntry>();
    const paths = await this.listVaultFiles();
    for (const path of paths) {
      if (shouldSkipPath(path)) continue;
      const stat = await this.app.vault.adapter.stat(path);
      if (!stat || stat.type !== "file") continue;
      afterEntries.set(path, {
        path,
        mtime: stat.mtime,
        size: stat.size,
        eligible: isEligiblePath(path),
        snapshotted: false,
      });
    }

    const changes: CheckpointChange[] = [];
    const keepBefore = new Set<string>();

    for (const [path, after] of afterEntries) {
      const prev = before.get(path);
      if (!prev) {
        changes.push({
          path,
          op: "create",
          unrestorable: false,
        });
        continue;
      }
      if (prev.mtime !== after.mtime || prev.size !== after.size) {
        const unrestorable = !prev.snapshotted;
        changes.push({ path, op: "modify", unrestorable });
        if (prev.snapshotted) keepBefore.add(path);
      }
    }

    for (const [path, prev] of before) {
      if (afterEntries.has(path)) continue;
      const unrestorable = !prev.snapshotted;
      changes.push({ path, op: "delete", unrestorable });
      if (prev.snapshotted) keepBefore.add(path);
    }

    await this.pruneBeforeCopies(root, keepBefore);

    const manifest: ApplyCheckpointManifest = {
      id: checkpointId,
      createdAt: Date.now(),
      applyMessageId,
      changes,
    };
    await this.app.vault.adapter.write(
      normalizePath(`${root}/manifest.json`),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );

    // Drop inventory after finalize to save space.
    if (await this.app.vault.adapter.exists(inventoryPath)) {
      await this.app.vault.adapter.remove(inventoryPath);
    }

    return manifest;
  }

  async undo(
    conversationId: string,
    checkpointId: string,
  ): Promise<{ restored: number; skipped: number }> {
    const root = this.checkpointRoot(conversationId, checkpointId);
    const manifestPath = normalizePath(`${root}/manifest.json`);
    if (!(await this.app.vault.adapter.exists(manifestPath))) {
      throw new Error(`Checkpoint not found: ${checkpointId}`);
    }

    const manifest = JSON.parse(
      await this.app.vault.adapter.read(manifestPath),
    ) as ApplyCheckpointManifest;

    let restored = 0;
    let skipped = 0;
    const beforeRoot = normalizePath(`${root}/before`);

    for (const change of [...manifest.changes].reverse()) {
      if (change.unrestorable) {
        skipped += 1;
        continue;
      }

      if (change.op === "create") {
        if (await this.app.vault.adapter.exists(change.path)) {
          await this.app.vault.adapter.remove(change.path);
        }
        restored += 1;
        continue;
      }

      const snapshotPath = normalizePath(`${beforeRoot}/${change.path}`);
      if (!(await this.app.vault.adapter.exists(snapshotPath))) {
        skipped += 1;
        continue;
      }
      const data = await this.app.vault.adapter.readBinary(snapshotPath);
      await this.ensureParentDir(change.path);
      await this.app.vault.adapter.writeBinary(change.path, data);
      restored += 1;
    }

    await this.removeDirRecursive(root);
    return { restored, skipped };
  }

  async discard(
    conversationId: string,
    checkpointId: string,
  ): Promise<void> {
    const root = this.checkpointRoot(conversationId, checkpointId);
    if (await this.app.vault.adapter.exists(root)) {
      await this.removeDirRecursive(root);
    }
  }

  async deleteConversationCheckpoints(conversationId: string): Promise<void> {
    const dir = this.conversationDir(conversationId);
    if (await this.app.vault.adapter.exists(dir)) {
      await this.removeDirRecursive(dir);
    }
  }

  private async listVaultFiles(): Promise<string[]> {
    const out: string[] = [];
    const walk = async (dir: string): Promise<void> => {
      const listed = await this.app.vault.adapter.list(dir);
      for (const file of listed.files) {
        out.push(normalizePath(file));
      }
      for (const folder of listed.folders) {
        const normalized = normalizePath(folder);
        if (shouldSkipPath(normalized)) continue;
        await walk(normalized);
      }
    };
    await walk("");
    return out;
  }

  private async ensureDir(path: string): Promise<void> {
    const normalized = normalizePath(path);
    if (await this.app.vault.adapter.exists(normalized)) return;
    const parts = normalized.split("/").filter(Boolean);
    let current = "";
    for (const part of parts) {
      current = current ? `${current}/${part}` : part;
      if (!(await this.app.vault.adapter.exists(current))) {
        await this.app.vault.adapter.mkdir(current);
      }
    }
  }

  private async ensureParentDir(filePath: string): Promise<void> {
    const normalized = normalizePath(filePath);
    const idx = normalized.lastIndexOf("/");
    if (idx <= 0) return;
    await this.ensureDir(normalized.slice(0, idx));
  }

  private async pruneBeforeCopies(
    root: string,
    keep: Set<string>,
  ): Promise<void> {
    const beforeRoot = normalizePath(`${root}/before`);
    if (!(await this.app.vault.adapter.exists(beforeRoot))) return;

    const walk = async (dir: string): Promise<void> => {
      const listed = await this.app.vault.adapter.list(dir);
      for (const file of listed.files) {
        const normalized = normalizePath(file);
        const rel = normalized.startsWith(`${beforeRoot}/`)
          ? normalized.slice(beforeRoot.length + 1)
          : normalized;
        if (!keep.has(rel)) {
          await this.app.vault.adapter.remove(normalized);
        }
      }
      for (const folder of listed.folders) {
        await walk(normalizePath(folder));
      }
    };
    await walk(beforeRoot);
  }

  private async removeDirRecursive(dir: string): Promise<void> {
    const normalized = normalizePath(dir);
    if (!(await this.app.vault.adapter.exists(normalized))) return;
    const listed = await this.app.vault.adapter.list(normalized);
    for (const file of listed.files) {
      await this.app.vault.adapter.remove(normalizePath(file));
    }
    for (const folder of listed.folders) {
      await this.removeDirRecursive(normalizePath(folder));
    }
    await this.app.vault.adapter.rmdir(normalized, false);
  }
}
