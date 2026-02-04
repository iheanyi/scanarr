import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  declare readonly dialogTarget: HTMLDialogElement

  open() {
    if (this.dialogTarget.open) return
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
}
