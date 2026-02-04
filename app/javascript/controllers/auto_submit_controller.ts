import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    const form = this.element.closest("form")
    if (form instanceof HTMLFormElement) {
      form.requestSubmit()
    }
  }
}
