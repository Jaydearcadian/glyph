/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        mono: ["'JetBrains Mono'", "ui-monospace", "monospace"],
      },
      colors: {
        glyph: {
          bg: "#05060a",
          panel: "#0b0e16",
          line: "#1b2233",
          accent: "#5eead4",
          accent2: "#a78bfa",
          danger: "#fb7185",
        },
      },
      boxShadow: {
        glow: "0 0 40px -8px rgba(94,234,212,0.45)",
      },
    },
  },
  plugins: [],
};
