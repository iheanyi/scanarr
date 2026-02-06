import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "toggle"]

  declare contentTarget: HTMLElement
  declare toggleTarget: HTMLElement

  expanded = false

  toggle() {
    this.expanded = !this.expanded
    if (this.expanded) {
      this.contentTarget.classList.remove("line-clamp-3")
      this.toggleTarget.textContent = "Show less"
    } else {
      this.contentTarget.classList.add("line-clamp-3")
      this.toggleTarget.textContent = "Show more"
    }
  }
}
