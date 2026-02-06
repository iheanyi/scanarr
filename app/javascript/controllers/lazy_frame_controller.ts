import { Controller } from "@hotwired/stimulus"

/**
 * Lazy-loads a turbo-frame when a sentinel element scrolls into view.
 *
 * Use this instead of Turbo's native `loading="lazy"` when the frame has
 * `display: contents` (e.g. inside a CSS Grid), which strips the frame's
 * box model and prevents Turbo's IntersectionObserver from firing.
 *
 * The sentinel target (a visible child div) retains its box model and
 * can be observed normally.
 */
export default class extends Controller {
  static values = { url: String }
  static targets = ["sentinel"]

  declare urlValue: string
  declare sentinelTarget: HTMLElement
  declare hasSentinelTarget: boolean

  private observer: IntersectionObserver | null = null

  connect() {
    if (!this.hasSentinelTarget || !this.urlValue) return

    this.observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) this.load()
      },
      { rootMargin: "400px" }
    )
    this.observer.observe(this.sentinelTarget)
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
  }

  private load() {
    this.observer?.disconnect()
    this.observer = null
    ;(this.element as HTMLElement).setAttribute("src", this.urlValue)
  }
}
