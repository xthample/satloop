/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        btc:  { orange:'#F7931A', dark:'#0D0D0D', panel:'#141414', border:'#252525', muted:'#666' },
        sat:  { green:'#00FF94', red:'#FF3B3B', yellow:'#FFD166' },
      },
      fontFamily: {
        display: ['"Space Mono"', 'monospace'],
        body:    ['"DM Sans"', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
