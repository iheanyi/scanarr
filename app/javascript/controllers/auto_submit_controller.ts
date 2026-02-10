import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: Number }

  declare readonly delayValue: number
  declare readonly hasDelayValue: boolean

  private debounceTimer: ReturnType<typeof setTimeout> | null = null

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = null
    }
  }

  submit() {
    this.submitForm()
  }

  submitDebounced() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    const delay = this.hasDelayValue ? this.delayValue : 180
    this.debounceTimer = setTimeout(() => this.submitForm(), delay)
  }

  private submitForm() {
    const form = this.element.closest("form")
    if (!(form instanceof HTMLFormElement)) return

    form.requestSubmit()
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = null
    }
  }
}
