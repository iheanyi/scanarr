import { vi, beforeEach, afterEach } from 'vitest'

// Create a mock location that works with jsdom
beforeEach(() => {
  // Use a simpler mock approach that doesn't conflict with jsdom
  Object.defineProperty(window, 'location', {
    value: {
      href: 'http://localhost/',
      origin: 'http://localhost',
      search: '',
      pathname: '/',
      host: 'localhost',
      hostname: 'localhost',
      protocol: 'http:',
      port: '',
      hash: '',
      assign: vi.fn(),
      replace: vi.fn(),
      reload: vi.fn(),
    },
    writable: true,
    configurable: true,
  })

  // Mock history.replaceState
  vi.spyOn(window.history, 'replaceState').mockImplementation(() => {})
})

afterEach(() => {
  vi.restoreAllMocks()
})
