import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filter", "option", "checkbox", "chips", "count", "summary", "panel", "trigger", "empty"]
  static values = {
    allLabel: String,
    maxChips: Number,
    noneLabel: String,
    open: Boolean
  }

  declare readonly filterTarget: HTMLInputElement
  declare readonly hasFilterTarget: boolean
  declare readonly optionTargets: HTMLElement[]
  declare readonly checkboxTargets: HTMLInputElement[]
  declare readonly chipsTarget: HTMLElement
  declare readonly countTarget: HTMLElement
  declare readonly summaryTarget: HTMLElement
  declare readonly panelTarget: HTMLElement
  declare readonly triggerTarget: HTMLButtonElement
  declare readonly emptyTarget: HTMLElement
  declare readonly hasChipsTarget: boolean
  declare readonly hasCountTarget: boolean
  declare readonly hasSummaryTarget: boolean
  declare readonly hasPanelTarget: boolean
  declare readonly hasTriggerTarget: boolean
  declare readonly hasEmptyTarget: boolean
  declare readonly hasAllLabelValue: boolean
  declare readonly allLabelValue: string
  declare readonly hasMaxChipsValue: boolean
  declare readonly maxChipsValue: number
  declare readonly hasNoneLabelValue: boolean
  declare readonly noneLabelValue: string
  declare openValue: boolean

  private handleDocumentClick = (event: MouseEvent) => {
    if (!this.element.contains(event.target as Node)) {
      this.close()
    }
  }

  private handleKeydown = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      this.close()
    }
  }

  connect() {
    this.update()
    this.close()
    document.addEventListener("click", this.handleDocumentClick)
    document.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.handleDocumentClick)
    document.removeEventListener("keydown", this.handleKeydown)
  }

  toggle(event: Event) {
    event.stopPropagation()
    if (this.openValue) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("hidden")
    }
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "true")
    }
    this.openValue = true
    if (this.hasFilterTarget) {
      this.filterTarget.focus()
    }
  }

  close() {
    if (this.hasPanelTarget) {
      this.panelTarget.classList.add("hidden")
    }
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "false")
    }
    this.openValue = false
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
    this.updateSummary(selected)
    this.updateChips(selected)
    this.updateEmptyState(selected.length)
  }

  changed() {
    this.update()
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }

  remove(event: Event) {
    event.preventDefault()
    event.stopPropagation()
    const target = event.currentTarget as HTMLElement | null
    const value = target?.dataset.value
    if (!value) return

    const checkbox = this.checkboxTargets.find((input) => input.value === value)
    if (!checkbox) return

    checkbox.checked = false
    this.update()
  }

  private updateSummary(selected: HTMLInputElement[]) {
    const count = selected.length
    const total = this.checkboxTargets.length
    const allLabel = this.hasAllLabelValue ? this.allLabelValue : "All"
    const noneLabel = this.hasNoneLabelValue ? this.noneLabelValue : "None selected"

    if (this.hasSummaryTarget) {
      if (count === 0) {
        this.summaryTarget.textContent = noneLabel
      } else if (count === total) {
        this.summaryTarget.textContent = allLabel
      } else {
        this.summaryTarget.textContent = selected[0]?.dataset.label || selected[0]?.value || ""
      }
    }

    if (!this.hasCountTarget) return

    if (count === 0) {
      this.countTarget.textContent = ""
      this.countTarget.classList.add("hidden")
    } else if (count === total) {
      this.countTarget.textContent = ""
      this.countTarget.classList.add("hidden")
    } else if (count === 1) {
      this.countTarget.textContent = ""
      this.countTarget.classList.add("hidden")
    } else {
      this.countTarget.textContent = `+${count - 1}`
      this.countTarget.classList.remove("hidden")
    }
  }

  private updateEmptyState(count: number) {
    if (!this.hasEmptyTarget) return
    this.emptyTarget.classList.toggle("hidden", count > 0)
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
      chip.className = "inline-flex items-center gap-1.5 rounded-md border border-border bg-surface-2 px-2.5 py-1 text-xs font-medium text-foreground"

      const text = document.createElement("span")
      text.textContent = label

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "inline-flex h-4 w-4 items-center justify-center rounded text-muted hover:bg-surface hover:text-foreground transition-colors"
      remove.innerHTML = `<svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/></svg>`
      remove.setAttribute("aria-label", `Remove ${label}`)
      remove.setAttribute("data-action", "click->multi-select#remove")
      remove.dataset.value = checkbox.value

      chip.appendChild(text)
      chip.appendChild(remove)
      this.chipsTarget.appendChild(chip)
    })

    if (overflow > 0) {
      const chip = document.createElement("span")
      chip.className = "rounded-md border border-border bg-surface-2 px-2.5 py-1 text-xs font-medium text-muted"
      chip.textContent = `+${overflow}`
      this.chipsTarget.appendChild(chip)
    }
  }
}
