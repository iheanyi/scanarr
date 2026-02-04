import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filter", "option", "checkbox", "chips", "count", "panel", "trigger", "empty"]
  static values = {
    allLabel: String,
    maxChips: Number,
    open: Boolean
  }

  declare readonly filterTarget: HTMLInputElement
  declare readonly hasFilterTarget: boolean
  declare readonly optionTargets: HTMLElement[]
  declare readonly checkboxTargets: HTMLInputElement[]
  declare readonly chipsTarget: HTMLElement
  declare readonly countTarget: HTMLElement
  declare readonly panelTarget: HTMLElement
  declare readonly triggerTarget: HTMLButtonElement
  declare readonly emptyTarget: HTMLElement
  declare readonly hasChipsTarget: boolean
  declare readonly hasCountTarget: boolean
  declare readonly hasPanelTarget: boolean
  declare readonly hasTriggerTarget: boolean
  declare readonly hasEmptyTarget: boolean
  declare readonly hasAllLabelValue: boolean
  declare readonly allLabelValue: string
  declare readonly hasMaxChipsValue: boolean
  declare readonly maxChipsValue: number
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
    this.updateCount(selected.length)
    this.updateChips(selected)
    this.updateEmptyState(selected.length)
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

  private updateCount(count: number) {
    if (!this.hasCountTarget) return
    const total = this.checkboxTargets.length
    const allLabel = this.hasAllLabelValue ? this.allLabelValue : "All"

    if (count === 0) {
      this.countTarget.textContent = "None selected"
    } else if (count === total) {
      this.countTarget.textContent = allLabel
    } else {
      this.countTarget.textContent = `${count} selected`
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
      chip.className = "inline-flex items-center gap-1 rounded-full border border-zinc-800 bg-zinc-900 px-2 py-0.5 text-xs text-zinc-300"

      const text = document.createElement("span")
      text.textContent = label

      const remove = document.createElement("span")
      remove.className = "inline-flex h-4 w-4 items-center justify-center rounded-full text-zinc-400 hover:bg-zinc-800 hover:text-zinc-200"
      remove.textContent = "x"
      remove.setAttribute("role", "button")
      remove.setAttribute("aria-label", `Remove ${label}`)
      remove.setAttribute("data-action", "click->multi-select#remove")
      remove.dataset.value = checkbox.value

      chip.appendChild(text)
      chip.appendChild(remove)
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
