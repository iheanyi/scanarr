import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["page", "viewport", "progressText", "progressBar", "progressPercent"]
  static values = { style: String, pageCount: Number, initialPageIndex: Number, progressUrl: String }
  declare readonly pageTargets: HTMLElement[]
  declare readonly viewportTarget: HTMLElement
  declare readonly hasViewportTarget: boolean
  declare readonly progressTextTarget: HTMLElement
  declare readonly progressBarTarget: HTMLElement
  declare readonly progressPercentTarget: HTMLElement
  declare readonly hasProgressTextTarget: boolean
  declare readonly hasProgressBarTarget: boolean
  declare readonly hasProgressPercentTarget: boolean
  declare readonly styleValue: string
  declare readonly pageCountValue: number
  declare readonly initialPageIndexValue: number
  declare readonly progressUrlValue: string
  declare readonly hasProgressUrlValue: boolean

  private currentIndex = 0
  private observer?: IntersectionObserver
  private lastReportedIndex = -1

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.handleKeydown)
    const initialIndex = this.initialPageIndexValue ? this.initialPageIndexValue - 1 : 0
    if (this.pageTargets.length > 0) {
      this.currentIndex = Math.min(Math.max(initialIndex, 0), this.pageTargets.length - 1)
      this.updateProgressUI()
      this.observePages()
    }
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleKeydown)
    this.observer?.disconnect()
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
    this.updateProgressUI()
  }

  private isHorizontal() {
    return this.styleValue === "left_to_right" || this.styleValue === "right_to_left"
  }

  private observePages() {
    if (this.pageTargets.length === 0) return
    const root = this.hasViewportTarget ? this.viewportTarget : null
    this.observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0]
        if (!visible) return

        const index = this.pageTargets.indexOf(visible.target as HTMLElement)
        if (index >= 0 && index !== this.currentIndex) {
          this.currentIndex = index
          this.updateProgressUI()
        }
      },
      { root, threshold: [0.6] }
    )

    this.pageTargets.forEach((page) => this.observer?.observe(page))
  }

  private updateProgressUI() {
    const pageCount = this.pageCountValue || this.pageTargets.length
    if (!pageCount) return

    const pageIndex = Math.min(this.currentIndex + 1, pageCount)
    const percent = Math.min(100, Math.round((pageIndex / pageCount) * 100))

    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `Page ${pageIndex} / ${pageCount}`
    }
    if (this.hasProgressPercentTarget) {
      this.progressPercentTarget.textContent = `${percent}%`
    }
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${percent}%`
    }

    if (pageIndex !== this.lastReportedIndex) {
      this.lastReportedIndex = pageIndex
      this.persistProgress(pageIndex, pageCount)
    }
  }

  private persistProgress(pageIndex: number, pageCount: number) {
    if (!this.hasProgressUrlValue || !this.progressUrlValue) return
    const token = document
      .querySelector('meta[name="csrf-token"]')
      ?.getAttribute("content")

    fetch(this.progressUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token || ""
      },
      body: JSON.stringify({ page_index: pageIndex, page_count: pageCount })
    }).catch(() => {})
  }
}
