import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "item", "count"]

  declare inputTarget: HTMLInputElement
  declare itemTargets: HTMLElement[]
  declare countTarget: HTMLElement

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()
    let visible = 0

    this.itemTargets.forEach((item) => {
      const text = (item.dataset.chapterFilterText || item.textContent || "").toLowerCase()
      const match = !query || text.includes(query)
      item.style.display = match ? "" : "none"
      if (match) visible++
    })

    this.countTarget.textContent = `${visible} of ${this.itemTargets.length}`
  }
}
