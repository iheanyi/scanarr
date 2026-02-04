import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  declare readonly menuTarget: HTMLElement
  declare readonly hasMenuTarget: boolean

  private handleDocumentClick = this.closeOnClickOutside.bind(this)
  private handleKeydown = this.onKeydown.bind(this)

  connect() {
    // Close dropdown when clicking outside
    document.addEventListener("click", this.handleDocumentClick)
    document.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.handleDocumentClick)
    document.removeEventListener("keydown", this.handleKeydown)
  }

  toggle(event: Event) {
    event.stopPropagation()
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.toggle("hidden")
  }

  close() {
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.add("hidden")
  }

  closeOnClickOutside(event: Event) {
    if (!this.element.contains(event.target as Node)) {
      this.close()
    }
  }

  onKeydown(event: KeyboardEvent) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}
