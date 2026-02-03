import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  declare readonly menuTarget: HTMLElement

  connect() {
    // Close dropdown when clicking outside
    document.addEventListener("click", this.closeOnClickOutside.bind(this))
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnClickOutside.bind(this))
  }

  toggle(event: Event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.add("hidden")
  }

  closeOnClickOutside(event: Event) {
    if (!this.element.contains(event.target as Node)) {
      this.close()
    }
  }
}
