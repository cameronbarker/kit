import { App, FuzzySuggestModal, TFile } from "obsidian";

export class DocumentMentionModal extends FuzzySuggestModal<TFile> {
  private readonly onChoose: (file: TFile) => void;
  private readonly excludePaths: Set<string>;

  constructor(
    app: App,
    excludePaths: Iterable<string>,
    onChoose: (file: TFile) => void,
  ) {
    super(app);
    this.excludePaths = new Set(excludePaths);
    this.onChoose = onChoose;
    this.setPlaceholder("Select a document…");
  }

  getItems(): TFile[] {
    return this.app.vault
      .getMarkdownFiles()
      .filter((file) => !this.excludePaths.has(file.path))
      .sort((a, b) => a.path.localeCompare(b.path));
  }

  getItemText(file: TFile): string {
    return file.path;
  }

  onChooseItem(file: TFile): void {
    this.onChoose(file);
  }
}
