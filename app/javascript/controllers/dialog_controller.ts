import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  declare readonly dialogTarget: HTMLDialogElement

  private previouslyFocusedElement: HTMLElement | null = null

  open() {
    if (this.dialogTarget.open) return

    this.previouslyFocusedElement = document.activeElement instanceof HTMLElement ? document.activeElement : null
    this.dialogTarget.showModal()
  }

  close() {
    if (!this.dialogTarget.open) return

    this.dialogTarget.close()
  }

  closeOnBackdrop(event: MouseEvent) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  restoreFocus() {
    this.previouslyFocusedElement?.focus()
    this.previouslyFocusedElement = null
  }
}
