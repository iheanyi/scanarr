import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "count"]

  declare checkboxTargets: HTMLInputElement[]
  declare hasCountTarget: boolean
  declare countTarget: HTMLElement

  connect() {
    this.updateCount()
  }

  selectAll() {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = true
    })
    this.updateCount()
  }

  clearAll() {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = false
    })
    this.updateCount()
  }

  toggle() {
    this.updateCount()
  }

  private updateCount() {
    if (!this.hasCountTarget) return
    const selectedCount = this.checkboxTargets.filter((checkbox) => checkbox.checked).length
    this.countTarget.textContent = `${selectedCount} selected`
  }
}
