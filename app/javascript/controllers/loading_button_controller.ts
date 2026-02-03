import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["button", "text", "spinner", "icon"];

  declare readonly buttonTarget: HTMLButtonElement;
  declare readonly textTarget: HTMLElement;
  declare readonly spinnerTarget: HTMLElement;
  declare readonly iconTarget: HTMLElement;

  submit() {
    this.buttonTarget.disabled = true;
    this.buttonTarget.classList.add("opacity-75", "cursor-wait");
    this.textTarget.textContent = "Queueing...";
    this.spinnerTarget.classList.remove("hidden");
    this.iconTarget.classList.add("hidden");
  }
}
