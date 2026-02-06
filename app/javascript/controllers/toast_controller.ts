import { Controller } from "@hotwired/stimulus"

/**
 * Toast notification controller — Geist-inspired.
 *
 * Slides in from the bottom, auto-dismisses after a configurable delay,
 * and slides out on dismiss. Handles its own lifecycle (removes from DOM).
 */
export default class ToastController extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  declare delayValue: number
  private timeout: ReturnType<typeof setTimeout> | null = null

  connect() {
    // Force layout before adding the visible class so the transition fires
    const el = this.element as HTMLElement
    el.offsetHeight // force reflow
    requestAnimationFrame(() => {
      el.classList.remove("translate-y-2", "opacity-0")
      el.classList.add("translate-y-0", "opacity-100")
    })

    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  dismiss() {
    if (this.timeout) clearTimeout(this.timeout)
    const el = this.element as HTMLElement
    el.classList.remove("translate-y-0", "opacity-100")
    el.classList.add("translate-y-2", "opacity-0")
    el.addEventListener("transitionend", () => el.remove(), { once: true })
    // Fallback: remove after 400ms if transitionend doesn't fire
    setTimeout(() => el.remove(), 400)
  }
}
