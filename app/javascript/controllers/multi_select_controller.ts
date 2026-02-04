import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filter", "option", "checkbox", "chips", "count"]
  static values = {
    allLabel: String,
    maxChips: Number
  }

  declare readonly filterTarget: HTMLInputElement
  declare readonly optionTargets: HTMLElement[]
  declare readonly checkboxTargets: HTMLInputElement[]
  declare readonly chipsTarget: HTMLElement
  declare readonly countTarget: HTMLElement
  declare readonly hasChipsTarget: boolean
  declare readonly hasCountTarget: boolean
  declare readonly hasAllLabelValue: boolean
  declare readonly allLabelValue: string
  declare readonly hasMaxChipsValue: boolean
  declare readonly maxChipsValue: number

  connect() {
    this.update()
  }

  filter() {
    const query = this.filterTarget.value.trim().toLowerCase()
    this.optionTargets.forEach((option) => {
      const label = option.dataset.optionLabel || option.textContent || ""
      const match = query.length === 0 || label.toLowerCase().includes(query)
      option.classList.toggle("hidden", !match)
    })
  }

  update() {
    const selected = this.checkboxTargets.filter((checkbox) => checkbox.checked)
    this.updateCount(selected.length)
    this.updateChips(selected)
  }

  private updateCount(count: number) {
    if (!this.hasCountTarget) return
    const total = this.checkboxTargets.length
    const allLabel = this.hasAllLabelValue ? this.allLabelValue : "All"

    if (count === 0 || count === total) {
      this.countTarget.textContent = allLabel
    } else {
      this.countTarget.textContent = `${count} selected`
    }
  }

  private updateChips(selected: HTMLInputElement[]) {
    if (!this.hasChipsTarget) return
    const maxChips = this.hasMaxChipsValue ? this.maxChipsValue : 4
    const visible = selected.slice(0, maxChips)
    const overflow = selected.length - visible.length

    this.chipsTarget.innerHTML = ""

    visible.forEach((checkbox) => {
      const label = checkbox.dataset.label || checkbox.value
      const chip = document.createElement("span")
      chip.className = "rounded-full border border-zinc-800 bg-zinc-900 px-2 py-0.5 text-xs text-zinc-300"
      chip.textContent = label
      this.chipsTarget.appendChild(chip)
    })

    if (overflow > 0) {
      const chip = document.createElement("span")
      chip.className = "rounded-full border border-zinc-800 bg-zinc-900 px-2 py-0.5 text-xs text-zinc-500"
      chip.textContent = `+${overflow}`
      this.chipsTarget.appendChild(chip)
    }
  }
}
