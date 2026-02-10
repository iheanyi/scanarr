import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  declare readonly menuTarget: HTMLElement
  declare readonly hasMenuTarget: boolean
  declare readonly buttonTarget: HTMLElement
  declare readonly hasButtonTarget: boolean

  private handleDocumentClick = this.closeOnClickOutside.bind(this)
  private handleKeydown = this.onKeydown.bind(this)

  connect() {
    // Close dropdown when clicking outside
    document.addEventListener("click", this.handleDocumentClick)
    document.addEventListener("keydown", this.handleKeydown)
    this.setExpanded(false)
  }

  disconnect() {
    document.removeEventListener("click", this.handleDocumentClick)
    document.removeEventListener("keydown", this.handleKeydown)
  }

  toggle(event: Event) {
    event.stopPropagation()
    if (!this.hasMenuTarget) return
    const isHidden = this.menuTarget.classList.contains("hidden")
    this.menuTarget.classList.toggle("hidden")
    this.setExpanded(isHidden)
  }

  close() {
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.add("hidden")
    this.setExpanded(false)
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

  private setExpanded(expanded: boolean) {
    if (!this.hasButtonTarget) return
    this.buttonTarget.setAttribute("aria-expanded", String(expanded))
  }
}
