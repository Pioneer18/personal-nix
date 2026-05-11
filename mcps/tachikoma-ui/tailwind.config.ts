import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: "class",
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        background: "rgb(9 9 11)",   // zinc-950
        card: "rgb(24 24 27)",       // zinc-900
        border: "rgb(39 39 42)",     // zinc-800
        primary: "rgb(244 244 245)", // zinc-100
        secondary: "rgb(161 161 170)", // zinc-400
        muted: "rgb(113 113 122)",   // zinc-500
      },
      fontFamily: {
        mono: ["JetBrains Mono", "Fira Code", "Consolas", "monospace"],
      },
    },
  },
  plugins: [],
};

export default config;
