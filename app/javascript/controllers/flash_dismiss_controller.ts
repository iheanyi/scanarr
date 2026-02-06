import { Controller } from "@hotwired/stimulus"

export default class FlashDismissController extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  declare delayValue: number
  private timeout: ReturnType<typeof setTimeout> | null = null

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  dismiss() {
    const el = this.element as HTMLElement
    el.style.transition = "opacity 300ms ease-out"
    el.style.opacity = "0"
    setTimeout(() => el.remove(), 300)
  }
}
