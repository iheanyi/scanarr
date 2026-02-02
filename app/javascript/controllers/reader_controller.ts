import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["page"]
  static values = { style: String }
  declare readonly pageTargets: HTMLElement[]
  declare readonly styleValue: string

  private currentIndex = 0

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleKeydown)
  }

  private handleKeydown(event: KeyboardEvent) {
    if (event.key === "ArrowRight" || event.key === "j") {
      this.next()
    } else if (event.key === "ArrowLeft" || event.key === "k") {
      this.previous()
    }
  }

  private next() {
    this.scrollToIndex(this.currentIndex + 1)
  }

  private previous() {
    this.scrollToIndex(this.currentIndex - 1)
  }

  private scrollToIndex(index: number) {
    if (index < 0 || index >= this.pageTargets.length) return
    this.currentIndex = index
    const block = this.isHorizontal() ? "nearest" : "start"
    const inline = this.isHorizontal() ? "start" : "nearest"
    this.pageTargets[index].scrollIntoView({ behavior: "smooth", block, inline })
  }

  private isHorizontal() {
    return this.styleValue === "left_to_right" || this.styleValue === "right_to_left"
  }
}
