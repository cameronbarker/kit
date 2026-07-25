import { Notice } from "obsidian";

export class HelloService {
  greet(): void {
    new Notice("Hello from Kit");
  }
}
