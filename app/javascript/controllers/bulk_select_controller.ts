import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "selectAll", "actionBar", "count", "chapterIds", "actionName"]

  declare checkboxTargets: HTMLInputElement[]
  declare selectAllTarget: HTMLInputElement
  declare hasSelectAllTarget: boolean
  declare actionBarTarget: HTMLElement
  declare countTarget: HTMLElement
  declare chapterIdsTarget: HTMLInputElement
  declare actionNameTarget: HTMLInputElement

  private lastCheckedIndex: number | null = null
  private shiftHeld = false

  connect() {
    this.captureShift = this.captureShift.bind(this)
    document.addEventListener("mousedown", this.captureShift as EventListener)
  }

  disconnect() {
    document.removeEventListener("mousedown", this.captureShift as EventListener)
  }

  private captureShift(event: MouseEvent) {
    this.shiftHeld = event.shiftKey
  }

  toggle(event: Event) {
    const target =
      (event.target as HTMLElement).closest("input[type='checkbox']") as HTMLInputElement |
      null || (event.currentTarget as HTMLInputElement)
    const visible = this.visibleCheckboxes()
    const currentIndex = visible.indexOf(target)

    if (this.shiftHeld && this.lastCheckedIndex !== null && currentIndex !== -1) {
      const start = Math.min(this.lastCheckedIndex, currentIndex)
      const end = Math.max(this.lastCheckedIndex, currentIndex)
      const checked = target.checked

      for (let i = start; i <= end; i++) {
        visible[i].checked = checked
      }
    }

    if (currentIndex !== -1) {
      this.lastCheckedIndex = currentIndex
    }

    this.updateUI()
  }

  toggleAll() {
    const checked = this.hasSelectAllTarget && this.selectAllTarget.checked
    this.visibleCheckboxes().forEach((cb) => (cb.checked = checked))
    this.lastCheckedIndex = null
    this.updateUI()
  }

  submitAction(event: Event) {
    const button = event.currentTarget as HTMLButtonElement
    const actionName = button.dataset.actionName
    if (!actionName) return

    const selected = this.selectedIds()
    if (selected.length === 0) return

    this.chapterIdsTarget.value = selected.join(",")
    this.actionNameTarget.value = actionName

    const form = this.chapterIdsTarget.closest("form") as HTMLFormElement
    form?.requestSubmit()
  }

  private visibleCheckboxes(): HTMLInputElement[] {
    return this.checkboxTargets.filter(
      (cb) => cb.closest("[data-chapter-filter-target='item']")?.style.display !== "none"
    )
  }

  private selectedIds(): string[] {
    return this.visibleCheckboxes()
      .filter((cb) => cb.checked)
      .map((cb) => cb.value)
  }

  private updateUI() {
    const selected = this.selectedIds()
    const count = selected.length

    // Toggle "selecting" class on the controller element — CSS uses this
    // to keep all checkboxes visible once any are checked
    this.element.classList.toggle("selecting", count > 0)

    // Toggle action bar visibility
    if (count > 0) {
      this.actionBarTarget.classList.remove("hidden")
    } else {
      this.actionBarTarget.classList.add("hidden")
    }

    this.countTarget.textContent = `${count} selected`

    // Update select-all state
    if (this.hasSelectAllTarget) {
      const visible = this.visibleCheckboxes()
      this.selectAllTarget.checked = visible.length > 0 && visible.every((cb) => cb.checked)
      this.selectAllTarget.indeterminate = count > 0 && count < visible.length
    }
  }
}
