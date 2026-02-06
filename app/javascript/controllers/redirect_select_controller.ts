import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  navigate(event: Event) {
    const select = event.target as HTMLSelectElement
    if (select.value) {
      window.location.href = select.value
    }
  }
}
